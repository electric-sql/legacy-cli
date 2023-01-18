defmodule ElectricCli.Config.Environment do
  alias ElectricCli.Config.Replication

  @derive Jason.Encoder
  @type t() :: %__MODULE__{
          replication: %Replication{}
        }
  defstruct [
    :replication
  ]

  use ExConstructor

  def new(map) do
    struct = super(map)

    replication =
      case struct.replication do
        nil ->
          nil

        alt ->
          alt
          |> Replication.new()
      end

    %{struct | replication: replication}
  end
end
