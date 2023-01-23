defmodule ElectricMigrations.Ast.IndexColumn do
  @enforce_keys [
    :rank,
    :column_name,
    :direction,
    :collating_sequence,
    :key?
  ]

  defstruct [
    :rank,
    :column_name,
    :direction,
    :collating_sequence,
    key?: true
  ]

  @type t() :: %__MODULE__{
          rank: non_neg_integer(),
          column_name: String.t() | nil,
          direction: :asc | :desc,
          collating_sequence: String.t(),
          key?: boolean()
        }
end
