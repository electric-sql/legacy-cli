defmodule Electric.Migrations.Generation do
  @moduledoc """
  Generates PostgreSQL text from SQLite text
  """

  @type flavour() :: :postgresql | :sqlite
  alias Electric.Migrations.Parse, as: Parse

  @doc """
  Given an ordered list of Electric.Migration objects creates a PostgreSQL file for the last migration in the list
  """
  def postgres_for_ordered_migrations(ordered_migrations) do
    case before_and_after_ast(ordered_migrations) do
      {:ok, before_ast, after_ast} ->
        postgres_string = get_postgres_for_ast_changes(before_ast, after_ast)
        {:ok, postgres_string}

      {:error, reasons} ->
        {:error, reasons}
    end
  end

  defp before_and_after_ast(migration_set) do
    case Parse.sql_ast_from_migration_set(migration_set) do
      {:ok, after_ast} ->
        all_but_last_migration_set = Enum.drop(migration_set, -1)

        case Parse.sql_ast_from_migration_set(all_but_last_migration_set) do
          {:ok, before_ast} ->
            {:ok, before_ast, after_ast}

          {:error, reasons} ->
            {:error, reasons}
        end

      {:error, reasons} ->
        {:error, reasons}
    end
  end

  defp get_postgres_for_ast_changes(before_ast, after_ast) do
    get_sql_for_ast_changes(before_ast, after_ast, :postgresql)
  end

  #  defp _get_sqlite_for_ast_changes(before_ast, after_ast) do
  #    get_sql_for_ast_changes(before_ast, after_ast, :sqlite)
  #  end

  defp get_sql_for_ast_changes(before_ast, after_ast, flavour) do
    for change <- table_changes(before_ast, after_ast), into: "" do
      case change do
        {nil, table_after} ->
          build_sql_create_table(table_after, flavour)

        {table_before, nil} ->
          build_sql_drop_table(table_before)

        {table_before, table_after} ->
          build_sql_alter_table(table_before, table_after, flavour)
      end
    end
  end

  defp table_full_name(table_info) do
    "#{table_info.namespace}.#{table_info.table_name}"
  end

  defp build_sql_create_table(table_info, flavour) do
    ## https://www.sqlite.org/syntax/column-constraint.html
    ## %{cid: 0, dflt_value: nil, name: "id", notnull: 0, pk: 1, type: "INTEGER"}

    column_definitions =
      Enum.map(table_info.column_infos, fn {_, info} ->
        "\n  " <> column_def_sql_from_info(info, flavour)
      end)

    foreign_key_clauses =
      for foreign_key_info <- table_info.foreign_keys_info do
        "\n  " <> foreign_key_sql_from_info(foreign_key_info, flavour)
      end

    columns_and_keys = Enum.join(column_definitions ++ foreign_key_clauses, ",")

    case flavour do
      :postgresql ->
        "\nCREATE TABLE #{table_full_name(table_info)} (#{columns_and_keys});\n"

      :sqlite ->
        "\nCREATE TABLE #{table_full_name(table_info)} (#{columns_and_keys})STRICT;\n"
    end
  end

  defp build_sql_drop_table(table_info) do
    "DROP TABLE #{table_full_name(table_info)};\n"
  end

  defp build_sql_alter_table(table_before, table_after, flavour) do
    ## add columns
    added_colums_lines =
      for {column_id, column_info} <- table_after.column_infos,
          not Map.has_key?(table_before.column_infos, column_id) do
        "ALTER TABLE #{table_full_name(table_after)} ADD COLUMN #{column_def_sql_from_info(column_info, flavour)};\n"
      end

    ## delete columns
    dropped_colums_lines =
      for {column_id, column_info} <- table_before.column_infos,
          not Map.has_key?(table_after.column_infos, column_id) do
        "ALTER TABLE #{table_full_name(table_after)} DROP COLUMN #{column_info.name};\n"
      end

    ## rename columns
    rename_colums_lines =
      for {column_id, column_info} <- table_after.column_infos,
          Map.has_key?(table_before.column_infos, column_id) &&
            column_info.name != table_before.column_infos[column_id].name do
        "ALTER TABLE #{table_full_name(table_after)} RENAME COLUMN #{table_before.column_infos[column_id].name} TO #{column_info.name};\n"
      end

    all_change_lines = added_colums_lines ++ dropped_colums_lines ++ rename_colums_lines
    Enum.join(all_change_lines, " ")
  end

  defp table_changes(nil, after_ast) do
    for {_, table_info} <- after_ast do
      {nil, table_info}
    end
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

  defp foreign_key_sql_from_info(key_info, flavour) do
    # TODO DEFERRABLE
    # key_info looks like this %{from: "daddy", id: 0, match: "NONE", on_delete: "NO ACTION", on_update: "NO ACTION", seq: 0, table: "parent", to: "id"}

    elements =
      []
      # force postgres to MATCH SIMPLE as sqlite always does this
      |> prepend_if(flavour == :postgresql, "MATCH SIMPLE")
      |> prepend_if(key_info.on_delete != "NO ACTION", "ON DELETE #{key_info.on_delete}")
      |> prepend_if(key_info.on_update != "NO ACTION", "ON UPDATE #{key_info.on_update}")

    elements = [
      "FOREIGN KEY(#{key_info.from}) REFERENCES #{key_info.table}(#{key_info.to})" | elements
    ]

    Enum.join(elements, " ")
  end

  defp column_def_sql_from_info(column_info, flavour) do
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

    type_lookup =
      case flavour do
        :postgresql ->
          %{
            "TEXT" => "text",
            "NUMERIC" => "numeric",
            "INTEGER" => "integer",
            "REAL" => "real",
            "BLOB" => "blob"
          }

        _ ->
          %{
            "TEXT" => "TEXT",
            "NUMERIC" => "NUMERIC",
            "INTEGER" => "INTEGER",
            "REAL" => "REAL",
            "BLOB" => "BLOB"
          }
      end

    sorting = if column_info.pk_desc, do: " DESC", else: ""

    elements =
      []
      |> prepend_if(column_info.dflt_value != nil, "DEFAULT #{column_info.dflt_value}")
      |> prepend_if(column_info.unique, "UNIQUE")
      |> prepend_if(column_info.notnull != 0 && column_info.pk == 0, "NOT NULL")
      |> prepend_if(column_info.pk != 0, "PRIMARY KEY#{sorting}")

    elements = [type_lookup[column_info.type] | elements]
    elements = [column_info.name | elements]
    Enum.join(elements, " ")
  end
end
