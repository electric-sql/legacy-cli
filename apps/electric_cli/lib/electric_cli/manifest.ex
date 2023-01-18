defmodule ElectricCli.Manifest do
  @moduledoc """
  Manages the `electric.json` configuration file.
  """
  alias __MODULE__
  alias __MODULE__.Migration

  @filename "manifest.json"

  @derive Jason.Encoder
  @type t() :: %Manifest{
          app: binary(),
          env: binary(),
          migrations: [%Migration{}]
        }
  @enforce_keys [
    :app,
    :migrations
  ]
  defstruct [
    :app,
    :env,
    :migrations
  ]

  use ExConstructor

  @doc """
  Checks whether the config file already exists in the `dir` provided.

  If so, returns `{true, filepath}`. Otherwise returns `false`.
  """
  def exists?(dir) do
    path = filepath(dir)

    with true <- File.exists?(path) do
      {true, path}
    end
  end

  @doc """
  Initialise a new empty manifest file.
  """
  def init(app, dir) do
    dir = Path.expand(dir)

    attrs = %{
      app: app,
      migrations: []
    }

    attrs
    |> Manifest.new()
    |> Manifest.save(dir)
  end

  @doc """
  Load the manifest file into a `%Manifest{}` struct.
  """
  def load(app, dir, should_verify_app \\ true) do
    dir = Path.expand(dir)
    relative_dir = Path.relative_to_cwd(dir)

    with {:exists, {true, path}} <- {:exists, exists?(dir)},
         {:ok, json_str} <- File.read(path),
         {:ok, data} <- Jason.decode(json_str) do
      case {should_verify_app, Map.get(data, "app")} do
        {true, candidate} when candidate != app ->
          {:error,
           "Existing migrations in `#{relative_dir}`) are for a different app: `#{candidate}`."}

        _ ->
          {:ok, Manifest.new(data)}
      end
    else
      {:exists, false} ->
        {:error, "`#{@filename}` is missing in `#{relative_dir}`"}
    end
  end

  @doc """
  Saves the `%Manifest{}` into the manifest file.
  """
  def save(%Manifest{} = manifest, dir) do
    with {:ok, json} <- Jason.encode(manifest, pretty: true) do
      dir
      |> filepath()
      |> File.write(json <> "\n")
    end
  end

  @doc """
  Appends the `%Migration{}` to the `%Manifest{}` file.
  """
  def append_migration(%Manifest{} = manifest, %Migration{} = migration, dir) do
    manifest
    |> Map.update!(:migrations, &Enum.concat(&1, [migration]))
    |> save(dir)
  end

  @doc """
  Update the `%Manifest{}` into the manifest file.
  """
  def update_app(%Manifest{} = manifest, app, dir) do
    manifest
    |> Map.put(:app, app)
    |> save(dir)
  end

  defp filepath(dir) when is_binary(dir) do
    dir
    |> Path.join(@filename)
  end
end
