defmodule ElectricCli.Config.Environment do
  alias ElectricCli.Config.Replication

  @derive {Jason.Encoder, except: [:slug]}
  @type t() :: %__MODULE__{
          slug: binary(),
          replication: %Replication{}
        }
  @enforce_keys [
    :slug
  ]
  defstruct [
    :slug,
    :replication
  ]

  use ExConstructor

  def create(%{slug: existing} = map, slug) when existing == slug do
    map
    |> new()
  end

  def create(%{"slug" => existing} = map, slug) when existing == slug do
    map
    |> new()
  end

  def create(map, slug) when is_binary(slug) do
    map
    |> Map.put(:slug, slug)
    |> new()
  end

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
