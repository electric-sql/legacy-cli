defmodule ElectricCli.Config do
  @moduledoc """
  Manages the `electric.json` configuration file.
  """
  alias ElectricCli.Util
  alias ElectricCli.Validate
  alias ElectricCli.Config.Directories
  alias ElectricCli.Config.Environment

  alias __MODULE__

  @filename Application.compile_env!(:electric_cli, :config_filename)

  @derive {Jason.Encoder, except: [:root]}
  @type t() :: %Config{
          app: binary(),
          debug: boolean(),
          defaultEnv: binary(),
          directories: %Directories{},
          environments: %{
            binary() => %Environment{}
          },
          root: binary()
        }
  @enforce_keys [
    :app,
    :defaultEnv,
    :directories,
    :environments,
    :root
  ]
  defstruct [
    :app,
    :debug,
    :defaultEnv,
    :directories,
    :environments,
    :root
  ]

  use ExConstructor

  def new(map) do
    struct = super(map)

    directories =
      struct.directories
      |> Directories.new()

    environments =
      struct.environments
      |> Enum.map(fn {k, v} -> {k, Environment.new(v)} end)
      |> Enum.into(%{})

    %{struct | directories: directories, environments: environments}
  end

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
  Load the config file into a `%Config{}` struct.

  Also adds the current `root` dir and expands the `directories`
  so they're full paths rather than relative to the config file.
  """
  def load(dir) do
    dir = Path.expand(dir)

    with {:exists, {true, path}} <- {:exists, exists?(dir)},
         {:ok, json_str} <- File.read(path),
         {:ok, data} <- Jason.decode(json_str, keys: :atoms) do
      config =
        data
        |> Map.update!(:directories, &expand_dirs(&1, dir))
        |> Map.put(:root, dir)
        |> Config.new()

      {:ok, config}
    else
      {:exists, false} ->
        {:error, "`#{@filename}` file is missing in this directory",
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

  @doc """
  Saves the `%Config{}` into the config file.

  Contracts the `directories` so that they're stored relative to
  the config file (so they're easier to read and edit manually).
  """
  def save(%Config{root: root} = config) do
    config =
      config
      |> Map.update!(:directories, &contract_dirs(&1, root))
      |> Map.update!(:environments, &contract_envs/1)

    # IO.inspect({:saving, config})

    with {:ok, json} <- Jason.encode(config, pretty: true) do
      root
      |> filepath()
      |> File.write(json <> "\n")
    end
  end

  @doc """
  Lookup a configured environment by `env` name.
  """
  def target_environment(%Config{environments: environments}, env) do
    msg = "env `#{env}` not found; see `electric configure --help`"

    with :ok <- Validate.validate_slug(env),
         {:ok, key} <- Util.get_existing_atom(env, {:error, msg}),
         %Environment{} = environment <- Map.get(environments, key, {:error, msg}) do
      {:ok, environment}
    end
  end

  @doc """
  Given a %Config{} and a user specified `env`, return the `env` as an atom
  iff it matches an existing environment.
  """
  def existing_env_atom(%Config{defaultEnv: env}, nil) do
    {:ok, String.to_existing_atom(env)}
  end

  def existing_env_atom(%Config{} = config, env) when is_binary(env) do
    with {:ok, %Environment{}} <- target_environment(config, env) do
      {:ok, String.to_existing_atom(env)}
    else
      {:error, {:invalid, _}} ->
        {:error, "invalid env `#{env}`"}

      _ ->
        {:error, "env `#{env}` not found. See `electric config add_env`."}
    end
  end

  def contract_dirs(%Directories{} = directories, root) do
    directories
    |> Map.from_struct()
    |> Enum.map(fn {key, path} -> {key, Path.relative_to(path, root)} end)
    |> Directories.new()
  end

  defp contract_envs(env_map) do
    env_map
    |> Enum.map(fn {key, %Environment{} = env} -> {key, contract_env(env)} end)
    |> Enum.into(%{})
  end

  defp contract_env(%Environment{replication: nil} = env) when map_size(env) == 1 do
    %{}
  end

  defp contract_env(%Environment{} = env) do
    env
  end

  defp expand_dirs(dir_map, root) do
    dir_map
    |> Enum.map(fn {key, path} -> {key, Path.expand(path, root)} end)
    |> Enum.into(%{})
  end

  defp filepath(nil) do
    File.cwd!()
    |> filepath()
  end

  defp filepath(dir) when is_binary(dir) do
    dir
    |> Path.join(@filename)
  end
end
