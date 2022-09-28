defmodule Electric.Migrations.Triggers do
  @moduledoc """
  Adds triggers to the Satellite SQLite files with templates to allow integration with electric
  """

  @doc """
  Given an ordered set of Electric.Migration returns a templated version of the final migration
  SQL with all the triggers needed by Satellite added.
  """
  def add_triggers_to_last_migration(migration_set, template) do
    case Electric.Migrations.Parse.sql_ast_from_migration_set(migration_set) do
      {:error, reasons} ->
        {:error, reasons}

      ast ->
        sql_in = List.last(migration_set).original_body
        is_init = length(migration_set) == 1
        template_all_the_things(sql_in, ast, template, is_init)
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
