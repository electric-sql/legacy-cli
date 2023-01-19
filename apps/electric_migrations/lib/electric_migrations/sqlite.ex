defmodule ElectricMigrations.Sqlite do
  @moduledoc """
  Working with SQLite bodies and migrations
  """

  @doc """
  Adds triggers based on the provided template to the last migration in the list.

  Tries figuring out what tables are present after all the migrations are applied,
  and then provides that information to the template code.
  The `template` argument should be a quoted expression, for example result of `EEx.compile_string/2`,
  as it will be executed using `Code.eval_quoted/2` with the following variables set:
  - `is_init`: boolean, true if this is the first migration
  - `original_sql`: string, original sql of the migration
  - `tables`: a map of AST structs with table names as keys.
    See `t:ElectricMigrations.Ast.FullTableInfo.t/0` for documentation on AST structure
  """
  defdelegate add_triggers_to_last_migration(migrations, template),
    to: ElectricMigrations.Sqlite.Triggers,
    as: :add_triggers_to_last_migration

  @doc """
  Splits sql string into separate statements ignoring comments.
  """
  @spec get_statements(sql :: String.t()) :: [String.t()]
  defdelegate get_statements(sql), to: ElectricMigrations.Sqlite.Lexer

  @doc """
  Strips out comments from SQL
  """
  @spec strip_comments(sql :: String.t()) :: String.t()
  defdelegate strip_comments(sql), to: ElectricMigrations.Sqlite.Lexer
end
