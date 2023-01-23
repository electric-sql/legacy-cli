defmodule ElectricMigrations do
  @moduledoc """
  Parse ElectricSQL SQLite migrations and build Postgres migrations based on them
  """

  @type raw_migration :: %{name: String.t(), original_body: String.t()}
end
