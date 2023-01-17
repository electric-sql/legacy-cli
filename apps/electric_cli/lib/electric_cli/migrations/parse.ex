defmodule ElectricCli.Migrations.Parse do
  @moduledoc """
  Creates an AST from SQL migrations
  """

  @allowed_sql_types ["integer", "real", "text", "blob"]
  @default_namespace "main"

  @doc """
  Given a set of Maps and returns an ugly map of maps containing info about the DB structure.
  Also validates the SQL and returns error messages if validation fails
  """
  def sql_ast_from_migrations(migrations) do
    case ast_from_ordered_migrations(migrations) do
      {ast, [], []} ->
        {:ok, ast, nil}

      {ast, [], warnings} ->
        {:ok, ast, warnings}

      {_ast, errors, _warnings} ->
        {:error, errors}
    end
  end

  defp check_for_namespaces(migrations) do
    namespaced =
      for migration <- migrations do
        namespaced_table_names(migration.original_body)
      end

    case List.flatten(namespaced) do
      [] ->
        :ok

      namespaced ->
        errors =
          for name <- namespaced do
            "The table #{name} has a database name. Please leave this out and only give the table name."
          end

        {:error, errors, []}
    end
  end

  def namespaced_table_names(sql) do
    for [_match, capture] <-
          Regex.scan(~r/create table[^(]*\ ([\w]+\.[\w]+)\W*\(/, String.downcase(sql)) do
      capture
    end
  end

  def apply_migrations(conn, migrations) do
    sql_errors =
      Enum.flat_map(migrations, fn migration ->
        case Exqlite.Sqlite3.execute(conn, migration.original_body) do
          {:error, reason} -> ["In migration #{migration.name} SQL error: #{reason}"]
          :ok -> []
        end
      end)

    case List.flatten(sql_errors) do
      [] ->
        :ok

      errors ->
        {:error, errors, []}
    end
  end

  @doc false
  def ast_from_ordered_migrations(migrations) do
    namespace = @default_namespace
    # get all the table names
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    with :ok <- check_for_namespaces(migrations),
         :ok <- apply_migrations(conn, migrations) do
      index_info = all_index_info_from_connection(conn)

      {:ok, statement} =
        Exqlite.Sqlite3.prepare(
          conn,
          "SELECT * FROM sqlite_master WHERE type='table' AND name!='_electric_oplog';"
        )

      info = get_rows_while(conn, statement, [])
      :ok = Exqlite.Sqlite3.release(conn, statement)

      ast =
        info
        |> generate_ast(namespace, index_info, conn)
        |> Map.new(fn info -> {"#{namespace}.#{info.table_name}", info} end)

      validation_fails =
        for {_table_name, info} <- ast, length(info.validation_fails) > 0 do
          info.validation_fails
        end

      warnings =
        for {_table_name, info} <- ast, length(info.warning_messages) > 0 do
          info.warning_messages
        end

      {ast, List.flatten(validation_fails), List.flatten(warnings)}
    end
  end

  defp generate_ast(all_table_infos, namespace, index_info, conn) do
    for table_info <- all_table_infos do
      generate_table_ast(table_info, namespace, index_info, conn)
    end
  end

  defp generate_table_ast(table_info, namespace, index_info, conn) do
    [type, name, tbl_name, rootpage, sql] = table_info

    validation_fails = check_sql(tbl_name, sql)
    warning_messages = check_sql_warnings(tbl_name, sql)

    # column names
    {:ok, info_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{tbl_name});")

    columns = Enum.reverse(get_rows_while(conn, info_statement, []))

    column_names =
      for [_cid, name, _type, _notnull, _dflt_value, _pk] <- columns do
        name
      end

    column_infos =
      for [cid, name, type, notnull, dflt_value, pk] <- columns, into: %{} do
        {cid,
         %{
           cid: cid,
           name: name,
           type: type,
           notnull: notnull,
           unique: is_unique(name, index_info["#{namespace}.#{tbl_name}"]),
           pk_desc: is_primary_desc(name, index_info["#{namespace}.#{tbl_name}"]),
           dflt_value: dflt_value,
           pk: pk
         }}
      end

    type_errors =
      for {_cid, info} <- column_infos,
          not Enum.member?(@allowed_sql_types, String.downcase(info.type)) do
        "The type #{info.type} for column #{info.name} in table #{name} is not allowed. Please use one of INTEGER, REAL, TEXT, BLOB"
      end

    not_null_errors =
      for {_cid, info} <- column_infos,
          info.pk == 1 && info.notnull == 0 do
        "The primary key #{info.name} in table #{name} isn't NOT NULL. Please add NOT NULL to this column."
      end

    case_errors =
      for {_cid, info} <- column_infos,
          String.downcase(info.name) != info.name do
        "The name of column #{info.name} in table #{name} is not allowed. Please only use lowercase for column names."
      end

    validation_fails = validation_fails ++ type_errors ++ not_null_errors ++ case_errors

    # private keys columns
    private_key_column_names =
      for [_cid, name, _type, _notnull, _dflt_value, pk] when pk == 1 <- columns do
        name
      end

    # foreign keys
    {:ok, foreign_statement} =
      Exqlite.Sqlite3.prepare(conn, "PRAGMA foreign_key_list(#{tbl_name});")

    foreign_keys_rows = get_rows_while(conn, foreign_statement, [])

    foreign_keys =
      for [_id, _seq, table, from, to, _on_update, _on_delete, _match] <-
            foreign_keys_rows do
        %{
          child_key: from,
          parent_key: to,
          table: "#{namespace}.#{table}"
        }
      end

    foreign_keys_info =
      for [id, seq, table, from, to, on_update, on_delete, match] <- foreign_keys_rows do
        %{
          id: id,
          seq: seq,
          table: table,
          from: from,
          to: to,
          on_update: on_update,
          on_delete: on_delete,
          match: match
        }
      end

    %{
      table_name: tbl_name,
      table_info: %{
        type: type,
        name: name,
        tbl_name: tbl_name,
        rootpage: rootpage,
        sql: sql
      },
      columns: column_names,
      namespace: namespace,
      primary: private_key_column_names,
      foreign_keys: foreign_keys,
      column_infos: column_infos,
      foreign_keys_info: foreign_keys_info,
      validation_fails: validation_fails,
      warning_messages: warning_messages
    }
  end

  defp check_sql(table_name, sql) do
    errors = []
    lower = String.downcase(sql)

    #    errors =
    #      if not String.contains?(lower, "strict") do
    #        [
    #          "The table #{table_name} is not STRICT."
    #          | errors
    #        ]
    #      else
    #        errors
    #      end

    if not String.contains?(lower, "without rowid") do
      [
        "The table #{table_name} is not WITHOUT ROWID."
        | errors
      ]
    else
      errors
    end
  end

  defp check_sql_warnings(_table_name, _sql) do
    []
  end

  def all_index_info(all_migrations) do
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    for migration <- all_migrations do
      :ok = Exqlite.Sqlite3.execute(conn, migration)
    end

    all_index_info_from_connection(conn)
  end

  defp all_index_info_from_connection(conn) do
    namespace = @default_namespace

    {:ok, statement} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT * FROM sqlite_master WHERE type='index';"
      )

    info = get_rows_while(conn, statement, [])
    :ok = Exqlite.Sqlite3.release(conn, statement)

    # for each table
    for [_type, _name, tbl_name, _rootpage, _sql] <- info, into: %{} do
      # column names
      {:ok, info_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA index_list(#{tbl_name});")

      indexes = Enum.reverse(get_rows_while(conn, info_statement, []))

      index_infos =
        for [seq, name, unique, origin, partial] <- indexes, into: %{} do
          {:ok, col_info_statement} =
            Exqlite.Sqlite3.prepare(conn, "PRAGMA index_xinfo(#{name});")

          index_columns = Enum.reverse(get_rows_while(conn, col_info_statement, []))

          index_column_infos =
            for [seqno, cid, name, desc, coll, key] <- index_columns do
              %{
                seqno: seqno,
                cid: cid,
                name: name,
                desc: desc,
                coll: coll,
                key: key
              }
            end

          {seq,
           %{
             seq: seq,
             name: name,
             unique: unique,
             origin: origin,
             partial: partial,
             columns: index_column_infos
           }}
        end

      {"#{namespace}.#{tbl_name}", index_infos}
    end
  end

  defp get_rows_while(conn, statement, rows) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, row} ->
        get_rows_while(conn, statement, [row | rows])

      :done ->
        rows
    end
  end

  defp is_unique(_column_name, nil) do
    false
  end

  defp is_unique(column_name, indexes) do
    matching_unique_indexes =
      for {_, info} <- indexes,
          info.origin == "u",
          key_column <- info.columns,
          key_column.key == 1 && key_column.name == column_name,
          do: true

    Enum.any?(matching_unique_indexes)
  end

  defp is_primary_desc(_column_name, nil) do
    false
  end

  defp is_primary_desc(column_name, indexes) do
    matching_desc_indexes =
      for {_, info} <- indexes,
          info.origin == "pk",
          key_column <- info.columns,
          key_column.key == 1 && key_column.name == column_name && key_column.desc == 1,
          do: true

    Enum.any?(matching_desc_indexes)
  end

  @doc false
  def ast_from_ordered_migrations2(migrations) do
    bodies =
      for migration <- migrations do
        migration.original_body
      end

    {simple_tables_info(bodies), [], []}
  end

  @doc false
  def simple_tables_info(all_migrations) do
    namespace = "main"
    # get all the table names
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    for migration <- all_migrations do
      :ok = Exqlite.Sqlite3.execute(conn, migration)
    end

    {:ok, statement} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name!='_electric_oplog';"
      )

    info = get_rows_while(conn, statement, [])
    :ok = Exqlite.Sqlite3.release(conn, statement)

    # for each table
    infos =
      for [table_name, _sql] <- info do
        # column names
        {:ok, info_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{table_name});")
        columns = Enum.reverse(get_rows_while(conn, info_statement, []))

        column_names =
          for [_cid, name, _type, _notnull, _dflt_value, _pk] <- columns do
            name
          end

        # private keys columns
        private_key_column_names =
          for [_cid, name, _type, _notnull, _dflt_value, pk] when pk == 1 <- columns do
            name
          end

        # foreign keys
        {:ok, foreign_statement} =
          Exqlite.Sqlite3.prepare(conn, "PRAGMA foreign_key_list(#{table_name});")

        foreign_keys = get_rows_while(conn, foreign_statement, [])

        foreign_keys =
          for [_a, _b, parent_table, child_key, parent_key, _c, _d, _e] <- foreign_keys do
            %{
              :child_key => child_key,
              :parent_key => parent_key,
              :table => "#{namespace}.#{parent_table}"
            }
          end

        %{
          :table_name => table_name,
          :columns => column_names,
          :namespace => namespace,
          :primary => private_key_column_names,
          :foreign_keys => foreign_keys
        }
      end

    Enum.into(infos, %{}, fn info -> {"#{namespace}.#{info.table_name}", info} end)
  end
end
