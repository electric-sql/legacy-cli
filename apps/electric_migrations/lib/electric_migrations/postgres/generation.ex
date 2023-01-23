defmodule ElectricMigrations.Postgres.Generation do
  @moduledoc """
  Generates PostgreSQL text from SQLite text
  """

  alias ElectricMigrations.Sqlite.Parse

  @default_postgres_namespace "public"

  @doc """
  Given an ordered list of SQLite migrations in the form of a List of Maps with %{original_body: <>, name: <>}
  creates PostgreSQL SQL for the last migration in the list
  """
  @spec postgres_sql_for_last_migration([ElectricMigrations.raw_migration(), ...]) ::
          {:ok, sql :: String.t(), warnings :: [String.t()] | nil}
          | {:error, errors :: [String.t(), ...]}
  def postgres_sql_for_last_migration(migrations) do
    case before_and_after_ast(migrations) do
      {:ok, before_ast, after_ast, warnings} ->
        postgres_string = get_postgres_for_ast_changes(before_ast, after_ast)
        {:ok, postgres_string, warnings}

      {:error, reasons} ->
        {:error, reasons}
    end
  end

  defp before_and_after_ast(migrations) do
    with {:ok, after_ast, after_warnings} <-
           Parse.sql_ast_from_migrations(migrations, @default_postgres_namespace),
         all_but_last_migration_set = Enum.drop(migrations, -1),
         {:ok, before_ast, _warnings} <-
           Parse.sql_ast_from_migrations(all_but_last_migration_set, @default_postgres_namespace) do
      {:ok, before_ast, after_ast, after_warnings}
    end
  end

  defp get_postgres_for_ast_changes(before_ast, after_ast) do
    get_sql_for_ast_changes(before_ast, after_ast)
  end

  defp get_sql_for_ast_changes(before_ast, after_ast) do
    for change <- table_changes(before_ast, after_ast) |> Enum.reverse(), into: "" do
      case change do
        {nil, table_after} ->
          build_sql_create_table(table_after)

        {table_before, nil} ->
          build_sql_drop_table(table_before)

        {table_before, table_after} ->
          build_sql_alter_table(table_before, table_after)
      end
    end
  end

  defp table_full_name(table_info) do
    "#{table_info.namespace}.#{table_info.table_name}"
  end

  defp build_sql_create_table(table_info) do
    ## https://www.sqlite.org/syntax/column-constraint.html
    ## %{cid: 0, dflt_value: nil, name: "id", notnull: 0, pk: 1, type: "INTEGER"}

    column_definitions =
      table_info.column_infos
      |> Enum.map(fn {_, info} -> info end)
      |> Enum.map(&column_def_sql_from_info(&1))

    foreign_key_clauses = Enum.map(table_info.foreign_keys_info, &foreign_key_sql_from_info(&1))

    columns_and_keys = "\n  " <> Enum.join(column_definitions ++ foreign_key_clauses, ",\n  ")

    """

    CREATE TABLE #{table_full_name(table_info)} (#{columns_and_keys});
    ALTER TABLE #{table_full_name(table_info)} REPLICA IDENTITY FULL;
    """
  end

  defp build_sql_drop_table(table_info) do
    "DROP TABLE #{table_full_name(table_info)};\n"
  end

  defp build_sql_alter_table(table_before, table_after) do
    ## add columns
    added_columns_lines =
      for {column_id, column_info} <- table_after.column_infos,
          not Map.has_key?(table_before.column_infos, column_id) do
        "ALTER TABLE #{table_full_name(table_after)} ADD COLUMN #{column_def_sql_from_info(column_info)};\n"
      end

    Enum.join(added_columns_lines, " ")
  end

  defp table_changes(before_ast, after_ast) do
    new_and_changed =
      for {table_name, table_info} <- after_ast, table_info != before_ast[table_name] do
        {before_ast[table_name], table_info}
      end

    dropped =
      for {table_name, table_info} <- before_ast, not Map.has_key?(after_ast, table_name) do
        {table_info, nil}
      end

    new_and_changed ++ dropped
  end

  defp prepend_if(list, true, item) when is_list(list), do: [item | list]
  defp prepend_if(list, false, _) when is_list(list), do: list

  defp foreign_key_sql_from_info(key_info) do
    # TODO DEFERRABLE
    # key_info looks like this %{from: "daddy", id: 0, match: "NONE", on_delete: "NO ACTION", on_update: "NO ACTION", seq: 0, table: "parent", to: "id"}

    elements =
      ["MATCH SIMPLE"]
      |> prepend_if(key_info.on_delete != "NO ACTION", "ON DELETE #{key_info.on_delete}")
      |> prepend_if(key_info.on_update != "NO ACTION", "ON UPDATE #{key_info.on_update}")

    elements = [
      "FOREIGN KEY(#{key_info.from}) REFERENCES #{key_info.table}(#{key_info.to})" | elements
    ]

    Enum.join(elements, " ")
  end

  defp column_def_sql_from_info(column_info) do
    # DONE
    # name
    # type

    # CONSTRAINTs done
    # PRIMARY KEY
    # NOT NULL
    # DEFAULT
    # PRIMARY KEY ASC
    # PRIMARY KEY DESC
    # UNIQUE

    # CONSTRAINTs TODO

    # AUTOINCREMENT disallow
    # COLLATE read from sql
    # GENERATED pass through somehow read from sql?
    # CHECK pass through somehow read from sql?

    # PRIMARY KEY conflict-clause this is sqlite stuff
    # NOT NULL conflict-clause this is sqlite stuff

    type_lookup = %{
      "text" => "text",
      "integer" => "bigint",
      "real" => "double precision",
      "blob" => "bytea"
    }

    col_type = type_lookup[String.downcase(column_info.type)]

    elements =
      []
      |> prepend_if(column_info.dflt_value != nil, "DEFAULT #{column_info.dflt_value}")
      |> prepend_if(column_info.unique, "UNIQUE")
      |> prepend_if(column_info.notnull && column_info.pk == 0, "NOT NULL")
      |> prepend_if(column_info.pk != 0, "PRIMARY KEY")

    elements = [col_type | elements]
    elements = [column_info.name | elements]
    Enum.join(elements, " ")
  end
end
