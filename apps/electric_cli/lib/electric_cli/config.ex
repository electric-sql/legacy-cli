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

  @app_symlink_name "@app"
  @config_symlink_name "@config"

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
      |> Enum.map(fn {k, v} -> {k, Environment.create(v, "#{k}")} end)
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
        |> Map.update!(:directories, &expand_directories(&1, dir))
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
  def save(
        %Config{
          app: app,
          defaultEnv: default_env,
          directories: %Directories{output: output_dir},
          root: root
        } = config
      ) do
    config =
      config
      |> Map.update!(:directories, &contract_directories(&1, root))
      |> Map.update!(:environments, &contract_environments/1)

    config_filepath =
      root
      |> filepath()

    with {:ok, json} <- Jason.encode(config, pretty: true),
         :ok <- File.write(config_filepath, json <> "\n"),
         :ok <- update_symlinks(app, default_env, output_dir) do
      :ok
    end
  end

  @doc """
  Lookup a configured environment by `env` name.
  """
  def target_environment(%Config{defaultEnv: default_env} = config, nil) do
    config
    |> target_environment(default_env)
  end

  def target_environment(%Config{environments: environments}, env) do
    msg = "env `#{env}` not found; see `electric configure --help`"

    with :ok <- Validate.validate_slug(env),
         {:ok, key} <- Util.get_existing_atom(env, {:error, msg}),
         %Environment{} = environment <- Map.get(environments, key, {:error, msg}) do
      {:ok, environment}
    else
      {:error, {:invalid, _}} ->
        {:error, "invalid env `#{env}`"}

      _ ->
        {:error, "env `#{env}` not found. See `electric config add_env`."}
    end
  end

  def contract_directories(%Directories{} = directories, root) do
    directories
    |> Map.from_struct()
    |> Enum.map(fn {key, path} -> {key, Path.relative_to(path, root)} end)
    |> Directories.new()
  end

  defp contract_environments(%{} = environments) do
    environments
    |> Enum.map(fn {key, %Environment{} = environment} ->
      {key, contract_environment(environment)}
    end)
    |> Enum.into(%{})
  end

  defp contract_environment(%Environment{replication: nil} = environment) do
    environment
    |> Map.from_struct()
    |> Map.drop([:replication])
  end

  defp contract_environment(%Environment{} = environment) do
    environment
  end

  defp expand_directories(%{} = directories, root) do
    directories
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

  defp update_symlinks(app, default_env, output_dir) do
    app_link_path = Path.join(output_dir, @app_symlink_name)
    config_link_path = Path.join(output_dir, @config_symlink_name)
    config_target = Path.join(app, default_env)

    with :ok <- File.mkdir_p(output_dir),
         :ok <- overwrite_symlink(app_link_path, app),
         :ok <- overwrite_symlink(config_link_path, config_target) do
      :ok
    end
  end

  defp overwrite_symlink(path, target) do
    with {:ok, _} <- File.rm_rf(path) do
      target
      |> File.ln_s(path)
    end
  end
end
