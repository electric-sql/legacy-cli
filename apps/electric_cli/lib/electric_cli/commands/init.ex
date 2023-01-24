defmodule ElectricCli.Commands.Init do
  use ElectricCli, :command

  alias ElectricCli.Apps
  alias ElectricCli.Migrations

  @options [
    env: [
      short: "-e",
      long: "--env",
      value_name: "ENV",
      help: "Name of the app environment.",
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

    Examples:
        electric init APP
        electric init APP --env ENV
    """
  end

  def spec do
    [
      name: "init",
      about: about(),
      flags:
        merge_flags(
          config_flags() ++
            replication_flags()
        ),
      options:
        merge_options(
          @options ++
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
    should_verify_app = not flags.no_verify

    migrations_dir = Path.relative_to(options.migrations_dir, root)
    output_dir = Path.relative_to(options.output_dir, root)

    with {:exists, false} <- {:exists, Config.exists?(root)},
         {:app, :ok} <- {:app, Validate.validate_slug(app)},
         {:env, :ok} <- {:env, Validate.validate_slug(env)},
         :ok <- Apps.can_show_app(app, should_verify_app) do
      replication =
        %{}
        |> Util.map_put_if("host", options.replication_host, not is_nil(options.replication_host))
        |> Util.map_put_if("port", options.replication_port, not is_nil(options.replication_port))
        |> Util.map_put_if(
          "ssl",
          not flags.replication_disable_ssl,
          not is_nil(options.replication_host)
        )

      environment =
        %{slug: String.to_atom(env)}
        |> Util.map_put_if("replication", replication, not Enum.empty?(replication))

      attrs = %{
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
      }

      config =
        attrs
        |> Config.new()

      with :ok <- Config.save(config),
           :ok <- Migrations.init_migrations(config) do
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
end
