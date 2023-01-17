defmodule ElectricMigrations.Sqlite.Triggers do
  @moduledoc """
  Adds triggers to the Satellite SQLite files with templates to allow integration with electric
  """

  alias ElectricMigrations.Sqlite.Parse

  @doc """
  Given an ordered set of Maps returns a templated version of the final migration
  SQL with all the triggers needed by Satellite added.
  """
  def add_triggers_to_last_migration(migration_set, template) do
    migrations =
      for migration <- migration_set do
        %{original_body: migration["original_body"], name: migration["name"]}
      end

    case Parse.sql_ast_from_migrations(migrations) do
      {:ok, ast, warnings} ->
        sql_in = List.last(migration_set)["original_body"]
        is_init = length(migration_set) == 1
        {template_all_the_things(sql_in, ast, template, is_init), warnings}

      {:error, errors} ->
        {:error, errors}
    end
  end

  @doc false
  def template_all_the_things(original_sql, tables, template, is_init) do
    ## strip the old header
    patched_sql = String.replace(original_sql, ~r/\A\/\*((?s).*)\*\/\n/, "")
    ## template
    {result, _bindings} =
      Code.eval_quoted(template,
        is_init: is_init,
        original_sql: patched_sql,
        tables: tables
      )

    result
  end
end
