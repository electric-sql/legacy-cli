defmodule ElectricMigrations.Ast.FullTableInfo do
  @moduledoc """
  A struct to hold SQLite table info structure
  """

  alias ElectricMigrations.Ast

  @enforce_keys [
    :table_name,
    :table_info,
    :namespace
  ]

  defstruct [
    :table_name,
    :table_info,
    :namespace,
    columns: [],
    indices: [],
    column_infos: [],
    primary: [],
    foreign_keys: [],
    foreign_keys_info: [],
    validation_fails: [],
    warning_messages: []
  ]

  @type fk() :: %{
          child_key: String.t(),
          parent_key: String.t(),
          table: String.t()
        }

  @type t() :: %__MODULE__{
          table_name: String.t(),
          table_info: Ast.TableInfo.t(),
          namespace: String.t(),
          columns: [String.t(), ...],
          column_infos: [Ast.ColumnInfo.t(), ...],
          primary: [String.t(), ...],
          foreign_keys: [fk()],
          foreign_keys_info: [Ast.ForeignKeyInfo.t()],
          validation_fails: [String.t()] | nil,
          warning_messages: [String.t()] | nil
        }
end
