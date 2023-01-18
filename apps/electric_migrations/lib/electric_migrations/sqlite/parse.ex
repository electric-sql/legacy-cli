defmodule ElectricMigrations.Sqlite.Parse do
  @moduledoc """
  Creates an AST from SQL migrations
  """
  alias ElectricMigrations.Ast
  alias ElectricMigrations.Sqlite.Introspect

  @allowed_sql_types ["integer", "real", "text", "blob"]

  @doc """
  Given a set of Maps and returns an ugly map of maps containing info about the DB structure.
  Also validates the SQL and returns error messages if validation fails
  """
  def sql_ast_from_migrations(migrations, default_namespace \\ "main") do
    case ast_from_ordered_migrations(migrations, default_namespace) do
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

  @doc """
  Get a list of all tables in the migration that mention database names.
  """
  def namespaced_table_names(sql) do
    for [_match, capture] <-
          Regex.scan(~r/create table[^(]*\ ([\w]+\.[\w]+)\W*\(/, String.downcase(sql)),
        uniq: true do
      capture
    end
  end

  defp apply_migrations(conn, migrations) do
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

  defp ast_from_ordered_migrations(migrations, namespace) do
    # get all the table names
    conn = Introspect.open_in_memory!()

    with :ok <- check_for_namespaces(migrations),
         :ok <- apply_migrations(conn, migrations) do
      # index_info = all_index_info_from_connection(conn, namespace)

      ast =
        Introspect.stream_all_tables(conn)
        |> generate_ast(namespace, conn)
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

  defp generate_ast(all_table_infos, namespace, conn) do
    for table_info <- all_table_infos do
      generate_table_ast(
        table_info,
        namespace,
        index_info_for_table(conn, table_info.tbl_name),
        conn
      )
    end
  end

  defp generate_table_ast(
         %Ast.TableInfo{tbl_name: tbl_name} = table_info,
         namespace,
         table_indices,
         conn
       ) do
    validation_fails = check_sql(tbl_name, table_info.sql)
    warning_messages = check_sql_warnings(tbl_name, table_info.sql)

    columns =
      Introspect.stream_all_columns(conn, tbl_name)
      |> Enum.map(fn %Ast.ColumnInfo{name: name} = info ->
        %{
          info
          | unique: is_unique(name, table_indices),
            pk_desc: is_primary_desc(name, table_indices)
        }
      end)

    column_names = Enum.map(columns, & &1.name)

    column_infos = Map.new(columns, &{&1.cid, &1})

    type_errors =
      for info <- columns, not Enum.member?(@allowed_sql_types, String.downcase(info.type)) do
        "The type #{info.type} for column #{info.name} in table #{table_info.name} is not allowed. Please use one of INTEGER, REAL, TEXT, BLOB"
      end

    # FIXME: `pk == 1` assumes that only one PK is ever going to be present
    not_null_errors =
      for info <- columns, info.pk == 1 && not info.notnull do
        "The primary key #{info.name} in table #{table_info.name} isn't NOT NULL. Please add NOT NULL to this column."
      end

    case_errors =
      for info <- columns, String.downcase(info.name) != info.name do
        "The name of column #{info.name} in table #{table_info.name} is not allowed. Please only use lowercase for column names."
      end

    validation_fails = validation_fails ++ type_errors ++ not_null_errors ++ case_errors

    # FIXME: `pk == 1` assumes that only one PK is ever going to be present
    # primary keys columns
    primary_key_column_names = Enum.filter(columns, &(&1.pk == 1)) |> Enum.map(& &1.name)

    foreign_keys_info = Introspect.stream_all_foreign_keys(conn, tbl_name) |> Enum.to_list()

    foreign_keys =
      for %Ast.ForeignKeyInfo{from: from, to: to, table: table} <-
            foreign_keys_info do
        %{
          child_key: from,
          parent_key: to,
          table: "#{namespace}.#{table}"
        }
      end

    %Ast.FullTableInfo{
      table_name: tbl_name,
      table_info: table_info,
      columns: column_names,
      namespace: namespace,
      primary: primary_key_column_names,
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

  defp index_info_for_table(conn, table_name) do
    Introspect.stream_all_indices(conn, table_name)
    |> Enum.to_list()
  end

  defp is_unique(column_name, indexes) do
    matching_unique_indexes =
      for info <- indexes,
          info.unique? and info.origin != :primary_key,
          key_column <- info.columns,
          key_column.key? and key_column.column_name == column_name,
          do: true

    Enum.any?(matching_unique_indexes)
  end

  defp is_primary_desc(column_name, indexes) do
    matching_desc_indexes =
      for info <- indexes,
          info.origin == :primary_key,
          key_column <- info.columns,
          key_column.key? and key_column.column_name == column_name and
            key_column.direction == :desc,
          do: true

    Enum.any?(matching_desc_indexes)
  end
end
