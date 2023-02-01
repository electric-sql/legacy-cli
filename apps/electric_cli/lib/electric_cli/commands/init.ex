defmodule ElectricCli.Commands.Init do
  use ElectricCli, :command

  alias ElectricCli.Apps
  alias ElectricCli.Migrations
  alias ElectricCli.Config.Environment

  @flags [
    sync_down: [
      long: "--sync-down",
      help: "Sync down the current migrations from the server.",
      required: false
    ]
  ]

  @options [
    env: [
      short: "-e",
      long: "--env",
      value_name: "ENV",
      help: "Name of the target environment.",
      parser: :string,
      default: Application.compile_env!(:electric_cli, :default_env)
    ]
  ]

  def about() do
    """
    Initialise a new application.

    Creates a new `electric.json` file with your local application configuration.
    Once initialised, further invocations of the `electric` CLI will use the
    values in this configuration as defaults for all commands.

    You can update your config and add environments using the `electric config`
    command. See `electric config --help` for details.

    Standard usage:

        electric init APP

    Specify a target environment:

        electric init APP --env ENV

    Sync down and bootstrap the local folder with the existing migrations
    from the server:

        electric init APP --sync-down
    """
  end

  def spec do
    [
      name: "init",
      about: about(),
      flags:
        merge_flags(
          @flags ++
            config_flags() ++
            console_flags() ++
            replication_flags()
        ),
      options:
        merge_options(
          @options ++
            console_options() ++
            directory_options() ++
            replication_options()
        ),
      args: [
        app: [
          parser: :string,
          required: true,
          help:
            "Application identifier (required). Generated when you create " <>
              "an application in the console.",
          value_name: "APP"
        ]
      ]
    ]
  end

  def init(%Optimus.ParseResult{args: args, flags: flags, options: options}) do
    root = Path.expand(options.root)
    relative_root = Path.relative_to_cwd(root)

    app = args.app
    env = options.env

    debug = flags.debug
    should_sync_down = flags.sync_down
    should_verify_app = not flags.no_verify

    migrations_dir = Path.relative_to(options.migrations_dir, root)
    output_dir = Path.relative_to(options.output_dir, root)

    with {:exists, false} <- {:exists, Config.exists?(root)},
         {:app, :ok} <- {:app, Validate.validate_slug(app)},
         {:env, :ok} <- {:env, Validate.validate_slug(env)},
         :ok <- Apps.can_show_app(app, should_verify_app) do
      environment =
        %{slug: String.to_atom(env)}
        |> Environment.new()
        |> Environment.put_optional(
          :console,
          options.console_host,
          options.console_port,
          flags.console_disable_ssl
        )
        |> Environment.put_optional(
          :replication,
          options.replication_host,
          options.replication_port,
          flags.replication_disable_ssl
        )

      config =
        Config.new(%{
          "app" => app,
          "debug" => debug,
          "defaultEnv" => env,
          "directories" => %{
            "migrations" => migrations_dir,
            "output" => output_dir
          },
          "environments" => %{
            env => environment
          },
          "root" => root
        })

      with :ok <- Config.save(config),
           {:ok, %Config{} = config} <- Config.load(root),
           :ok <- init_migrations(config, environment, should_sync_down, should_verify_app) do
        {:success, ["ElectricCli configuration written to `#{relative_root}/`\n"]}
      else
        _err ->
          {:error, "failed to save config file"}
      end
    else
      {:exists, {true, _path}} ->
        {:error, "project already initialised",
         [
           "Did you mean to run ",
           IO.ANSI.yellow(),
           "electric config update",
           IO.ANSI.reset(),
           " instead?"
         ]}

      alt ->
        alt
    end
  end

  defp init_migrations(%Config{} = config, %Environment{}, false, should_verify_app) do
    Migrations.init_migrations(config, should_verify_app)
  end

  defp init_migrations(%Config{} = config, %Environment{} = environment, true, _should_verify) do
    Migrations.sync_down_migrations(config, environment)
  end
end
