defmodule ElectricMigrations.Ast.IndexInfo do
  @enforce_keys [
    :seq,
    :name,
    :unique?,
    :origin,
    :partial?,
    :columns
  ]

  defstruct [
    :seq,
    :name,
    :unique?,
    :origin,
    :partial?,
    :columns
  ]

  @type t() :: %__MODULE__{
          seq: integer(),
          name: String.t(),
          origin: :create_index | :unique_constraint | :primary_key,
          unique?: boolean(),
          partial?: boolean(),
          columns: [ElectricMigrations.Ast.IndexColumn.t(), ...]
        }
end
