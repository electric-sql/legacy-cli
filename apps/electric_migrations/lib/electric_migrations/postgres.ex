defmodule ElectricMigrations.Postgres do
  @moduledoc """
  Working with Postgres migrations
  """

  @doc """
  Generate PostgreSQL body for the last migration in the provided list of SQLite migrations.
  """
  @spec postgres_sql_for_last_migration([ElectricMigrations.raw_migration(), ...]) ::
          {:ok, sql :: String.t(), warnings :: [String.t()] | nil}
          | {:error, errors :: [String.t(), ...]}
  defdelegate postgres_sql_for_last_migration(migrations),
    to: ElectricMigrations.Postgres.Generation
end
