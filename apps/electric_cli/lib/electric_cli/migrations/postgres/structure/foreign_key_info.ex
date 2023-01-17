defmodule ElectricCli.Databases.Postgres.Structure.ForeignKeyInfo do
  @moduledoc """
  A struct to hold SQLite foreign key info structure
  """

  @enforce_keys [
    :id,
    :seq,
    :table,
    :from,
    :to,
    :on_update,
    :on_delete,
    :match
  ]

  defstruct [
    :id,
    :seq,
    :table,
    :from,
    :to,
    :on_update,
    :on_delete,
    :match
  ]

  @type t() :: %__MODULE__{
          id: integer(),
          seq: integer(),
          table: String.t(),
          from: String.t(),
          to: String.t(),
          on_update: String.t(),
          on_delete: String.t(),
          match: String.t()
        }
end
