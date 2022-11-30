defmodule Electric.Databases.Postgres.Structure.FullTableInfo do
  @moduledoc """
  A struct to hold SQLite table info structure
  """

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
          table_info: Electric.Databases.Postgres.Structure.TableInfo.t(),
          namespace: String.t(),
          column_infos: [],
          foreign_keys_info: [],
          validation_fails: [] | nil,
          warning_messages: [] | nil
        }
end
