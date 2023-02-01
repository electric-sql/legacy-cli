defmodule ElectricCli.Config.Environment do
  alias ElectricCli.Config.Console
  alias ElectricCli.Config.Replication
  alias ElectricCli.Util
  alias __MODULE__

  @derive {Jason.Encoder, except: [:slug]}
  @type t() :: %Environment{
          console: %Console{},
          replication: %Replication{},
          slug: binary()
        }
  @enforce_keys [
    :slug
  ]
  defstruct [
    :console,
    :replication,
    :slug
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

    console =
      case struct.console do
        nil ->
          nil

        alt ->
          alt
          |> Console.new()
      end

    replication =
      case struct.replication do
        nil ->
          nil

        alt ->
          alt
          |> Replication.new()
      end

    %{struct | console: console, replication: replication}
  end

  @doc """
  Dry up some messy logic where we set the console and replication config
  for an environment, based on whether the values have been configured.

  We could dry up further by using the same struct for %Config{} and %Replication{}
  but this might bite us if the signature of the configured info needs to
  diverge in future.
  """
  @spec put_optional(
          %Environment{},
          :console | :replication,
          binary() | nil,
          integer() | nil,
          boolean()
        ) :: %Environment{}
  def put_optional(environment, key, host_option, port_option, disable_ssl_flag \\ false) do
    should_set_host = not is_nil(host_option)
    should_set_port = not is_nil(port_option)
    should_set_sql = should_set_host

    default =
      case key do
        :console -> %Console{}
        :replication -> %Replication{}
      end

    struct =
      case Map.get(environment, key) do
        nil ->
          default

        ^default = val ->
          val
      end

    struct =
      struct
      |> Util.map_put_if(:host, host_option, should_set_host)
      |> Util.map_put_if(:port, port_option, should_set_port)
      |> Util.map_put_if(:ssl, not disable_ssl_flag, should_set_sql)

    is_empty? =
      struct
      |> Map.from_struct()
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.empty?()

    {is_empty?, struct}

    environment
    |> Util.map_put_if(key, struct, not is_empty?)
  end
end
