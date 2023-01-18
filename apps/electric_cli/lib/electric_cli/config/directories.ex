defmodule ElectricCli.Config.Directories do
  @derive Jason.Encoder
  @type t() :: %__MODULE__{
          migrations: binary(),
          output: binary()
        }
  @enforce_keys [
    :migrations,
    :output
  ]
  defstruct [
    :migrations,
    :output
  ]

  use ExConstructor
end
