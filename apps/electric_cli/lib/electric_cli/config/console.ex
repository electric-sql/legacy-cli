defmodule ElectricCli.Config.Console do
  @derive Jason.Encoder
  @type t() :: %__MODULE__{
          host: binary(),
          port: integer(),
          ssl: boolean()
        }
  defstruct [
    :host,
    :port,
    :ssl
  ]

  use ExConstructor
end
