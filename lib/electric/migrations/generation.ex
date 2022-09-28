defmodule Electric.Migrations.Generation do
  @moduledoc """

  """

  def postgres_for_ordered_migrations(ordered_migrations) do
    {before_ast, after_ast} = before_and_after_ast(ordered_migrations)
    get_postgres_for_infos(before_ast, after_ast)
  end

  defp before_and_after_ast(migration_set) do
    after_ast = Electric.Migrations.Parse.sql_ast_from_migration_set(migration_set)
    all_but_last_migration_set = Enum.take(migration_set, Enum.count(migration_set) - 1)
    before_ast = Electric.Migrations.Parse.sql_ast_from_migration_set(all_but_last_migration_set)
    {before_ast, after_ast}
  end

  defp get_postgres_for_infos(before_ast, after_ast) do
    get_sql_for_infos(before_ast, after_ast, "postgres")
  end

  defp get_sqlite_for_infos(before_ast, after_ast) do
    get_sql_for_infos(before_ast, after_ast, "sqlite")
  end

  defp get_sql_for_infos(before_ast, after_ast, flavour) do
    statements =
      for change <- table_changes(before_ast, after_ast) do
        case change do
          {nil, table_after} ->
            ## https://www.sqlite.org/syntax/column-constraint.html
            ## %{cid: 0, dflt_value: nil, name: "id", notnull: 0, pk: 1, type: "INTEGER"}

            column_definitions =
              for {column_id, column_info} <- table_after.column_infos do
                "\n  " <> column_def_sql_from_info(column_info, flavour)
              end

            foreign_key_clauses =
              for foreign_key_info <- table_after.foreign_keys_info do
                "\n  " <> foreign_key_sql_from_info(foreign_key_info, flavour)
              end

            columns_and_keys = column_definitions ++ foreign_key_clauses

            case flavour do
              "postgres" ->
                "\nCREATE TABLE #{table_after.namespace}.#{table_after.table_name} (#{Enum.join(columns_and_keys, ",")});\n"

              "sqlite" ->
                "\nCREATE TABLE #{table_after.namespace}.#{table_after.table_name} (#{Enum.join(columns_and_keys, ",")})STRICT;\n"
            end

          {table_before, nil} ->
            "DROP TABLE #{table_before.namespace}.#{table_before.table_name};\n"

          {table_before, table_after} ->
            ## add columns
            added_colums_lines =
              for {column_id, column_info} <- table_after.column_infos,
                  !Map.has_key?(table_before.column_infos, column_id) do
                "ALTER TABLE #{table_after.namespace}.#{table_after.table_name} ADD COLUMN #{column_def_sql_from_info(column_info, flavour)};\n"
              end

            ## delete columns
            dropped_colums_lines =
              for {column_id, column_info} <- table_before.column_infos,
                  !Map.has_key?(table_after.column_infos, column_id) do
                "ALTER TABLE #{table_before.namespace}.#{table_before.table_name} DROP COLUMN #{column_info.name};\n"
              end

            ## rename columns
            rename_colums_lines =
              for {column_id, column_info} <- table_after.column_infos,
                  Map.has_key?(table_before.column_infos, column_id) &&
                    column_info.name != table_before.column_infos[column_id].name do
                "ALTER TABLE #{table_after.namespace}.#{table_after.table_name} RENAME COLUMN #{table_before.column_infos[column_id].name} TO #{column_info.name};\n"
              end

            all_change_lines = added_colums_lines ++ dropped_colums_lines ++ rename_colums_lines
            Enum.join(all_change_lines, " ")
        end
      end

    Enum.join(statements, "")
  end

  defp table_changes(before_ast, after_ast) do
    if before_ast == nil do
      for {table_name, table_info} <- after_ast do
        {nil, table_info}
      end
    else
      new_and_changed =
        for {table_name, table_info} <- after_ast, table_info != before_ast[table_name] do
          {before_ast[table_name], table_info}
        end

      dropped =
        for {table_name, table_info} <- before_ast, !Map.has_key?(after_ast, table_name) do
          {table_info, nil}
        end

      new_and_changed ++ dropped
    end
  end

  defp foreign_key_sql_from_info(key_info, flavour) do
    # DEFERRABLE

    # %{from: "daddy", id: 0, match: "NONE", on_delete: "NO ACTION", on_update: "NO ACTION", seq: 0, table: "parent", to: "id"}

    elements = []

    # force postgres to MATCH SIMPLE as sqlite always does this
    elements =
      case flavour do
        "postgres" ->
          ["MATCH SIMPLE" | elements]

        _ ->
          elements
      end

    elements =
      if key_info.on_delete != "NO ACTION" do
        ["ON DELETE #{key_info.on_delete}" | elements]
      else
        elements
      end

    elements =
      if key_info.on_update != "NO ACTION" do
        ["ON UPDATE #{key_info.on_update}" | elements]
      else
        elements
      end

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
        "postgres" ->
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

    elements = []

    elements =
      if column_info.dflt_value != nil do
        ["DEFAULT #{column_info.dflt_value}" | elements]
      else
        elements
      end

    elements =
      if column_info.unique do
        ["UNIQUE" | elements]
      else
        elements
      end

    elements =
      if column_info.notnull != 0 && column_info.pk == 0 do
        ["NOT NULL" | elements]
      else
        elements
      end

    elements =
      if column_info.pk != 0 do
        ["PRIMARY KEY#{if column_info.pk_desc do
          " DESC"
        else
          ""
        end}" | elements]
      else
        elements
      end

    elements = [type_lookup[column_info.type] | elements]
    elements = [column_info.name | elements]
    Enum.join(elements, " ")
  end
end
