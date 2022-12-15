defmodule Electric.Config do
  alias Electric.Migrations

  @derive Jason.Encoder

  @keys [
    :root,
    :app_id,
    :migrations_dir,
    :env
  ]

  @rc_filename ".electricrc"

  @enforce_keys @keys

  defstruct @keys

  @type t() :: %__MODULE__{
          root: binary(),
          app_id: binary(),
          migrations_dir: binary(),
          env: binary()
        }

  def new(args) do
    __struct__(args)
  end

  def keys do
    @keys
  end

  def cwd, do: File.cwd!()

  def path(dir \\ cwd()) do
    Path.join(dir, @rc_filename)
  end

  def load(dir \\ cwd()) do
    path = path(dir || cwd())

    with {:exists, true} <- {:exists, File.exists?(path)},
         {:ok, json} <- File.read(path),
         {:ok, map} <- Jason.decode(json, keys: :atoms!) do
      {:ok, new(map)}
    else
      {:exists, false} ->
        {:error, "Configuration file #{path} does not exist"}

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

  def init(%__MODULE__{} = config) do
    with {:ok, json} <- Jason.encode(config, pretty: true),
         {:ok, _} <- Migrations.init_migrations(config.app_id, config),
         path = path(config.root),
         :ok <- File.write(path, json) do
      {:ok, path}
    end
  end
end
