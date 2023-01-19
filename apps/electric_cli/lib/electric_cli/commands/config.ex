defmodule ElectricCli.Commands.Config do
  use ElectricCli, :command

  alias ElectricCli.Apps
  alias ElectricCli.Config
  alias ElectricCli.Config.Environment
  alias ElectricCli.Config.Replication
  alias ElectricCli.Migrations
  alias ElectricCli.Validate

  @options [
    app: [
      short: "-a",
      long: "--app",
      value_name: "APP",
      help: "Application identifier. Generated when you create an application in the console.",
      parser: :string
    ]
  ]

  def about do
    """
    Manage local application configuration.

    Updates the local application configuration stored in your `electric.json` file.
    """
  end

  def spec do
    [
      name: "config",
      about: about(),
      subcommands: [
        update: [
          name: "update",
          about: """
          Update your configuration.

          Supports updating your `app`, `defaultEnv`, `migrationsDir`, `outputDir`
          and `debug` mode, and the replication `host`, `port` and `ssl` mode of
          your default or specified env.
          """,
          flags:
            merge_flags(
              config_flags() ++
                replication_flags()
            ),
          options:
            merge_options(
              @options ++
                env_options() ++
                directory_options(false) ++
                replication_options()
            )
        ],
        add_env: [
          name: "add_env",
          about: """
          Add a new environment to your configuration.

          You can optionally specify the replication `host`, `port` and `ssl` mode
          and add the `--set-as-default` flag to change your default env to this one.
          """,
          args: [
            env: [
              parser: :string,
              required: true,
              help:
                "Environment identifier (required). Generated when you create " <>
                  "an environment in the console.",
              value_name: "ENV"
            ]
          ],
          flags:
            merge_flags(
              [
                default: [
                  long: "--set-as-default",
                  help: "Set this new env to be the default.",
                  required: false
                ]
              ] ++
                replication_flags()
            ),
          options: merge_options(replication_options())
        ],
        update_env: [
          name: "update_env",
          about: """
          Update the configuration of an environment.

          You can specify the replication `host`, `port` and `ssl` mode and add the
          `--set-as-default` flag to set the env as your default env.
          """,
          args: [
            env: [
              parser: :string,
              required: true,
              help: "Environment identifier (required).",
              value_name: "ENV"
            ]
          ],
          flags:
            merge_flags(
              [
                default: [
                  long: "--set-as-default",
                  help: "Set this new env to be the default.",
                  required: false
                ]
              ] ++
                replication_flags()
            ),
          options: merge_options(replication_options())
        ],
        remove_env: [
          name: "remove_env",
          about: """
          Remove an environment.

          Note that you can't remove your default env.
          """,
          args: [
            env: [
              parser: :string,
              required: true,
              help: "Environment identifier (required).",
              value_name: "ENV"
            ]
          ],
          options: default_options()
        ]
      ]
    ]
  end

  def update(%Optimus.ParseResult{options: options, flags: flags}) do
    root = Path.expand(options.root)
    relative_root = Path.relative_to_cwd(root)

    app = options.app
    env = options.env

    debug = flags.debug
    should_verify_app = not flags.no_verify

    migrations_dir =
      case options.migrations_dir do
        nil ->
          nil

        dir ->
          Path.expand(dir, root)
      end

    output_dir =
      case options.output_dir do
        nil ->
          nil

        dir ->
          Path.expand(dir, root)
      end

    with {:ok, %Config{directories: directories} = config} <- Config.load(root),
         {:ok, env_atom} <- Config.existing_env_atom(config, env),
         :ok <- Apps.can_show_app(app, should_verify_app) do
      environments = config.environments
      %Environment{} = environment = Map.fetch!(environments, env_atom)

      replication =
        case environment.replication do
          nil ->
            %Replication{}

          %Replication{} = value ->
            value
        end
        |> Util.map_put_if(:host, options.replication_host, not is_nil(options.replication_host))
        |> Util.map_put_if(:port, options.replication_port, not is_nil(options.replication_port))
        |> Util.map_put_if(
          :ssl,
          not flags.replication_disable_ssl,
          not is_nil(options.replication_host)
        )

      replication_empty? =
        replication
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Enum.empty?()

      environment =
        environment
        |> Util.map_put_if(:replication, replication, not replication_empty?)

      environments =
        environments
        |> Map.put(env_atom, environment)

      directories =
        directories
        |> Util.map_put_if(:migrations, migrations_dir, not is_nil(migrations_dir))
        |> Util.map_put_if(:output, output_dir, not is_nil(output_dir))

      new_config =
        config
        |> Util.map_put_if(:app, app, not is_nil(app))
        |> Map.put(:debug, debug)
        |> Map.put(:defaultEnv, "#{env_atom}")
        |> Map.put(:directories, directories)
        |> Map.put(:environments, environments)

      with true <- new_config != config,
           :ok <- Config.save(new_config),
           :ok <- Migrations.init_migrations(new_config, false),
           :ok <- Migrations.update_app(new_config) do
        {:success, ["ElectricCli configuration written to `#{relative_root}/`\n"]}
      else
        false ->
          {:success, "Nothing to update"}

        _err ->
          {:error, "failed to update config"}
      end
    end
  end

  def add_env(%Optimus.ParseResult{args: %{env: env}, options: options, flags: flags}) do
    root = Path.expand(options.root)

    env_atom = String.to_atom(env)
    should_set_default = flags.default

    with {:ok, %Config{environments: environments} = config} <- Config.load(root),
         :ok <- Validate.validate_slug(env),
         nil <- Map.get(environments, env_atom) do
      replication =
        %{}
        |> Util.map_put_if(:host, options.replication_host, not is_nil(options.replication_host))
        |> Util.map_put_if(:port, options.replication_port, not is_nil(options.replication_port))
        |> Util.map_put_if(
          :ssl,
          not flags.replication_disable_ssl,
          not is_nil(options.replication_host)
        )
        |> Replication.new()

      replication_empty? =
        replication
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Enum.empty?()

      environment =
        %{}
        |> Util.map_put_if(:replication, replication, not replication_empty?)
        |> Environment.new()

      environments =
        environments
        |> Map.put(env_atom, environment)

      new_config =
        config
        |> Util.map_put_if(:defaultEnv, env, should_set_default)
        |> Map.put(:environments, environments)

      with :ok <- Config.save(new_config) do
        {:success, ["New environment `#{env}` added successfully.\n"]}
      else
        _err ->
          {:error, "failed to update config"}
      end
    else
      %Environment{} ->
        {:error, "Environment `#{env}` already exists. Did you mean to update it?"}

      err ->
        err
    end
  end

  def update_env(%Optimus.ParseResult{args: %{env: env}, options: options, flags: flags}) do
    root = Path.expand(options.root)
    should_set_default = flags.default

    with {:ok, %Config{environments: environments} = config} <- Config.load(root),
         {:ok, env_atom} <- Config.existing_env_atom(config, env) do
      %Environment{replication: replication} = Map.fetch!(environments, env_atom)

      replication =
        case replication do
          nil ->
            %Replication{}

          %Replication{} = value ->
            value
        end
        |> Util.map_put_if(:host, options.replication_host, not is_nil(options.replication_host))
        |> Util.map_put_if(:port, options.replication_port, not is_nil(options.replication_port))
        |> Util.map_put_if(
          :ssl,
          not flags.replication_disable_ssl,
          not is_nil(options.replication_host)
        )

      replication_empty? =
        replication
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Enum.empty?()

      environment =
        %{}
        |> Util.map_put_if(:replication, replication, not replication_empty?)
        |> Environment.new()

      environments =
        environments
        |> Map.put(env_atom, environment)

      new_config =
        config
        |> Util.map_put_if(:defaultEnv, env, should_set_default)
        |> Map.put(:environments, environments)

      with :ok <- Config.save(new_config) do
        {:success, ["Environment `#{env}` updated successfully.\n"]}
      else
        _err ->
          {:error, "failed to update config"}
      end
    end
  end

  def remove_env(%Optimus.ParseResult{args: %{env: env}, options: options}) do
    root = Path.expand(options.root)

    with {:ok, %Config{defaultEnv: default_env, environments: environments} = config} <-
           Config.load(root),
         {:ok, env_atom} <- Config.existing_env_atom(config, env),
         false <- env == default_env do
      {_, environments} =
        environments
        |> Map.pop(env_atom)

      config = %{config | environments: environments}

      with :ok <- Config.save(config) do
        {:success, ["Environment `#{env}` removed successfully.\n"]}
      else
        _err ->
          {:error, "failed to update config"}
      end
    else
      true ->
        {:error, "You can't remove your default env."}

      err ->
        err
    end
  end
end
