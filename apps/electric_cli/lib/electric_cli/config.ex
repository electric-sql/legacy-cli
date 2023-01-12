defmodule ElectricCli.Config do
  alias ElectricCli.Migrations
  alias ElectricCli.Session
  alias ElectricCli.Client
  alias ElectricCli.Util
  alias __MODULE__

  @derive Jason.Encoder

  @keys [
    :app,
    :env,
    :migrations_dir,
    :root
  ]

  @rc_filename "electric.json"

  @enforce_keys @keys

  defstruct @keys

  @type t() :: %Config{
          app: binary(),
          env: binary(),
          migrations_dir: binary(),
          root: binary()
        }

  def new(args) do
    config = struct(__MODULE__, args)

    Map.update!(config, :migrations_dir, &Path.expand(&1, config.root))
  end

  def keys do
    @keys
  end

  def cwd, do: File.cwd!()

  def path(dir \\ cwd()) do
    Path.join(dir, @rc_filename)
  end

  def load(dir) do
    current_dir = dir || cwd()
    path = path(current_dir)

    with {:exists, true} <- {:exists, File.exists?(path)},
         {:ok, json} <- File.read(path),
         {:ok, map} <- Jason.decode(json, keys: :atoms!) do
      {:ok, new(Map.put(map, :root, current_dir))}
    else
      {:exists, false} ->
        {:error, "electric.json file is missing in this directory",
         [
           "Did you run ",
           IO.ANSI.yellow(),
           "electric init APP",
           IO.ANSI.reset(),
           " to make this project work with ElectricSQL?"
         ]}

      error ->
        error
    end
  end

  def merge(config, options) do
    Enum.reduce(@keys, %{}, fn key, acc ->
      value = options[key] || Map.fetch!(config, key)
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Initialize the `electric.json` config file according to the provided settings

  `no_verify` argument, if true, disables connection to the Console that makes sure
  that the app exist to prevent typos. This is an escape hatch for E2E tests to minimize
  external interactions.
  """
  def init(config, no_verify \\ false)

  def init(%Config{} = config, true) do
    file_contents =
      config
      |> Map.from_struct()
      |> Map.drop([:root])
      |> Map.update!(:migrations_dir, &Path.relative_to(&1, config.root))
      |> Util.rename_map_key(:migrations_dir, :migrations)

    with {:ok, json} <- Jason.encode(file_contents, pretty: true),
         {:ok, _} <- Migrations.init_migrations(config.app, config),
         path = path(config.root),
         :ok <- File.write(path, json <> "\n") do
      {:ok, path}
    end
  end

  def init(%Config{} = config, false) do
    with :ok <- Session.require_auth(),
         :ok <- check_if_app_exists(config.app) do
      init(config, true)
    end
  end

  defp check_if_app_exists(app) when is_binary(app) do
    with {:ok, apps} <- list_available_apps() do
      if app in apps do
        :ok
      else
        suggestion = Enum.max_by(apps, &String.jaro_distance(&1, app))

        error = "couldn't find app with id '#{app}'"

        error =
          if String.jaro_distance(suggestion, app) > 0.6,
            do: error <> ". Did you mean '#{suggestion}'?",
            else: error

        {:error, error,
         [
           "Did you create the app already? You can check with ",
           IO.ANSI.yellow(),
           "electric apps list",
           IO.ANSI.reset(),
           " to see all available apps"
         ]}
      end
    end
  end

  defp list_available_apps() do
    result = Client.get("apps")

    case result do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, Enum.map(data, & &1["id"])}

      {:ok, %Req.Response{}} ->
        {:error, "invalid credentials"}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end
end
