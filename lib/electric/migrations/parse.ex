defmodule Electric.Migrations.Parse do
  @moduledoc """
  Creates an AST from SQL migrations
  """

  @doc """
  Given a set of Electric.Migration and returns an ugly map of maps containing info about the DB structure.
  Also validates the SQL and returns error messages if validation fails
  """
  def sql_ast_from_migration_set(migrations) do
    case ast_from_ordered_migrations(migrations) do
      {ast, [], []} ->
        {:ok, ast, nil}

      {ast, [], warnings} ->
        {:ok, ast, Enum.join(warnings, "\n")}

      {_ast, errors, warnings} ->
        {:error, Enum.join(errors, "\n")}
    end
  end

  @doc false
  def ast_from_ordered_migrations(migrations) do
    namespace = "main"
    # get all the table names
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    sql_errors =
      Enum.flat_map(migrations, fn migration ->
        case Exqlite.Sqlite3.execute(conn, migration.original_body) do
          {:error, reason} -> ["In migration #{migration.name} SQL error: #{reason}"]
          :ok -> []
        end
      end)

    if length(sql_errors) > 0 do
      {:error, sql_errors, []}
    else
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
        for {table_name, info} <- ast, length(info.validation_fails) > 0 do
          info.validation_fails
        end

      warnings =
        for {table_name, info} <- ast, length(info.warning_messages) > 0 do
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
      for [_id, _seq, table, from, to, _on_update, _on_delete, _match] <- foreign_keys_rows do
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
    []
  end

  defp check_sql_warnings(table_name, sql) do
    warnings = []
    lower = String.downcase(sql)

    warnings =
      if not String.contains?(lower, "strict") do
        [
          "The table #{table_name} is not STRICT."
          | warnings
        ]
      else
        warnings
      end

    if not String.contains?(lower, "without rowid") do
      [
        "The table #{table_name} is not WITHOUT ROWID."
        | warnings
      ]
    else
      warnings
    end
  end

  def all_index_info(all_migrations) do
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    for migration <- all_migrations do
      :ok = Exqlite.Sqlite3.execute(conn, migration)
    end

    all_index_info_from_connection(conn)
  end

  defp all_index_info_from_connection(conn) do
    namespace = "main"

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

  defp is_unique(column_name, nil) do
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

  defp is_primary_desc(column_name, indexes) when indexes != nil do
    matching_desc_indexes =
      for {_, info} <- indexes,
          info.origin == "pk",
          key_column <- info.columns,
          key_column.key == 1 && key_column.name == column_name && key_column.desc == 1,
          do: true

    Enum.any?(matching_desc_indexes)
  end

  defp is_primary_desc(column_name, indexes) when indexes == nil do
    false
  end
end
