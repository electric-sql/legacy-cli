defmodule ElectricMigrations.Ast.TableInfo do
  @moduledoc """
  A struct to hold SQLite table info structure
  """

  @enforce_keys [
    :type,
    :name,
    :tbl_name,
    :rootpage,
    :sql
  ]

  defstruct [
    :type,
    :name,
    :tbl_name,
    :rootpage,
    :sql
  ]

  @type t() :: %__MODULE__{
          type: String.t(),
          name: String.t(),
          tbl_name: String.t(),
          rootpage: integer(),
          sql: String.t()
        }
end
