defmodule ElectricMigrations.Sqlite.Parse do
  @moduledoc """
  Creates an AST from SQL migrations
  """
  alias ElectricMigrations.Ast
  alias ElectricMigrations.Sqlite.Introspect

  @allowed_sql_types ["integer", "real", "text", "blob"]

  @type migration :: %{original_body: String.t(), name: String.t()}

  @doc """
  Given a set of Maps and returns an ugly map of maps containing info about the DB structure.
  Also validates the SQL and returns error messages if validation fails
  """
  @spec sql_ast_from_migrations([migration(), ...], String.t()) ::
          {:ok, %{required(String.t()) => Ast.FullTableInfo.t()}, nil}
          | {:error, [String.t(), ...]}
  def sql_ast_from_migrations(migrations, default_namespace \\ "main") do
    case ast_from_ordered_migrations(migrations, default_namespace) do
      {ast, [], []} ->
        {:ok, ast, nil}

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
    with :ok <- check_for_namespaces(migrations),
         conn = Introspect.open_in_memory!(),
         :ok <- apply_migrations(conn, migrations) do
      {validation_fails, ast} =
        Introspect.stream_all_tables(conn)
        |> Stream.map(&make_full_table_info(&1, namespace))
        |> Stream.map(&add_indices(&1, conn))
        |> Stream.map(&add_foreign_keys(&1, conn))
        |> Stream.map(&validate_sql_body/1)
        |> Stream.map(&get_and_validate_columns(&1, conn))
        |> Enum.flat_map_reduce(%{}, fn %Ast.FullTableInfo{} = info, ast ->
          {info.validation_fails, Map.put(ast, "#{namespace}.#{info.table_name}", info)}
        end)

      {ast, validation_fails, []}
    end
  end

  defp make_full_table_info(%Ast.TableInfo{} = base_info, namespace) do
    %Ast.FullTableInfo{
      table_name: base_info.tbl_name,
      namespace: namespace,
      table_info: base_info
    }
  end

  defp get_and_validate_columns(%Ast.FullTableInfo{} = info, conn) do
    {columns, %Ast.FullTableInfo{} = info} =
      Introspect.stream_all_columns(conn, info.table_name)
      |> Stream.map(&assign_column_properties(&1, info))
      |> Enum.map_reduce(info, fn col, %Ast.FullTableInfo{} = info ->
        errors = validate_column(col, info)
        {col, %{info | validation_fails: info.validation_fails ++ errors}}
      end)

    # FIXME: `pk == 1` assumes that only one PK is ever going to be present
    %{
      info
      | column_infos: Map.new(columns, &{&1.cid, &1}),
        primary: Enum.filter(columns, &(&1.pk == 1)) |> Enum.map(& &1.name),
        columns: Enum.map(columns, & &1.name)
    }
  end

  defp assign_column_properties(%Ast.ColumnInfo{name: name} = col, %Ast.FullTableInfo{} = info) do
    %{col | unique: is_unique(name, info.indices), pk_desc: is_primary_desc(name, info.indices)}
  end

  defp validate_column(%Ast.ColumnInfo{} = col, %Ast.FullTableInfo{} = info) do
    []
    |> add_if(
      String.downcase(col.type) not in @allowed_sql_types,
      "The type #{col.type} for column #{col.name} in table #{info.table_name} is not allowed. Please use one of INTEGER, REAL, TEXT, BLOB"
    )
    # FIXME: `pk == 1` assumes that only one PK is ever going to be present
    |> add_if(
      col.pk == 1 and not col.notnull,
      "The primary key #{col.name} in table #{info.table_name} must be NOT NULL. Please add NOT NULL to this column."
    )
    |> add_if(
      String.downcase(col.name) != col.name,
      "The name of column #{col.name} in table #{info.table_name} is not allowed. Please only use lowercase for column names."
    )
  end

  defp add_foreign_keys(%Ast.FullTableInfo{} = info, conn) do
    foreign_keys_info =
      Introspect.stream_all_foreign_keys(conn, info.table_name) |> Enum.to_list()

    foreign_keys =
      for %Ast.ForeignKeyInfo{from: from, to: to, table: table} <-
            foreign_keys_info do
        %{
          child_key: from,
          parent_key: to,
          table: "#{info.namespace}.#{table}"
        }
      end

    %{info | foreign_keys: foreign_keys, foreign_keys_info: foreign_keys_info}
  end

  defp validate_sql_body(%Ast.FullTableInfo{table_info: %{sql: sql}, table_name: name} = info) do
    sql = String.downcase(sql)

    errors =
      []
      |> add_if(
        not String.contains?(sql, "without rowid"),
        "The table #{name} is not WITHOUT ROWID."
      )

    Map.update!(info, :validation_fails, &(&1 ++ errors))
  end

  defp add_indices(%Ast.FullTableInfo{} = info, conn) do
    %{info | indices: Enum.to_list(Introspect.stream_all_indices(conn, info.table_name))}
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

  defp add_if(error_list, true, message), do: [message | error_list]
  defp add_if(error_list, false, _), do: error_list
end
