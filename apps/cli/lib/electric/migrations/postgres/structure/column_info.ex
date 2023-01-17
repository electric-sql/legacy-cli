defmodule Electric.Databases.Postgres.Structure.ColumnInfo do
  @moduledoc """
  A struct to hold SQLite table column info structure
  """

  @enforce_keys [
    :cid,
    :name,
    :type,
    :notnull,
    :unique,
    :pk_desc,
    :dflt_value,
    :pk
  ]

  defstruct [
    :cid,
    :name,
    :type,
    :notnull,
    :unique,
    :pk_desc,
    :dflt_value,
    :pk
  ]

  @type t() :: %__MODULE__{
          cid: integer(),
          name: String.t(),
          type: String.t(),
          notnull: integer(),
          unique: boolean(),
          pk_desc: boolean(),
          dflt_value: boolean() | nil,
          pk: integer()
        }
end
