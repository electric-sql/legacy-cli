defmodule ElectricMigrations.Ast.FullTableInfo do
  @moduledoc """
  A struct to hold SQLite table info structure
  """

  alias ElectricMigrations.Ast

  @enforce_keys [
    :table_name,
    :table_info,
    :namespace,
    :column_infos,
    :foreign_keys_info,
    :validation_fails,
    :warning_messages
  ]

  defstruct [
    :table_name,
    :table_info,
    :namespace,
    :column_infos,
    :foreign_keys_info,
    :validation_fails,
    :warning_messages
  ]

  @type t() :: %__MODULE__{
          table_name: String.t(),
          table_info: Ast.TableInfo.t(),
          namespace: String.t(),
          column_infos: [Ast.ColumnInfo.t(), ...],
          foreign_keys_info: [Ast.ForeignKeyInfo.t()],
          validation_fails: [String.t()] | nil,
          warning_messages: [String.t()] | nil
        }
end
