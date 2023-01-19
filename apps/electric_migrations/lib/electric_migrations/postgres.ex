defmodule ElectricMigrations.Postgres do
  @moduledoc """
  Working with Postgres migrations
  """

  @doc """
  Generate PostgreSQL body for the last migration in the provided list of SQLite migrations.
  """
  defdelegate postgres_sql_for_last_migration(migrations),
    to: ElectricMigrations.Postgres.Generation
end
