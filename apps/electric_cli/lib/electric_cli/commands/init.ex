defmodule ElectricCli.Commands.Init do
  use ElectricCli, :command

  alias ElectricCli.Apps
  alias ElectricCli.Config
  alias ElectricCli.Migrations
  alias ElectricCli.Validate

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
        %{}
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

  # @doc """
  # Initialize the `electric.json` config file according to the provided settings

  # `no_verify` argument, if true, disables connection to the Console that makes sure
  # that the app exist to prevent typos. This is an escape hatch for E2E tests to minimize
  # external interactions.
  # """
  # def init(config, no_verify \\ false)

  # def init(%Config{} = config, true) do
  #   file_contents =
  #     config
  #     |> Map.from_struct()
  #     |> Map.drop([:root])
  #     |> Map.update!(:migrations_dir, &Path.relative_to(&1, config.root))
  #     |> Util.rename_map_key(:migrations_dir, :migrations)

  #   with {:ok, json} <- Jason.encode(file_contents, pretty: true),
  #        {:ok, _} <- Migrations.init_migrations(config.app, config),
  #        path = path(config.root),
  #        :ok <- File.write(path, json <> "\n") do
  #     {:ok, path}
  #   end
  # end

  # def init(%Config{} = config, false) do
  #   with :ok <- Session.require_auth(),
  #        :ok <- check_if_app_exists(config.app) do
  #     init(config, true)
  #   end
  # end

  # defp check_if_app_exists(app) when is_binary(app) do
  #   with {:ok, apps} <- list_available_apps() do
  #     if app in apps do
  #       :ok
  #     else
  #       suggestion = Enum.max_by(apps, &String.jaro_distance(&1, app))

  #       error = "couldn't find app with id '#{app}'"

  #       error =
  #         if String.jaro_distance(suggestion, app) > 0.6,
  #           do: error <> ". Did you mean '#{suggestion}'?",
  #           else: error

  #       {:error, error,
  #        [
  #          "Did you create the app already? You can check with ",
  #          IO.ANSI.yellow(),
  #          "electric apps list",
  #          IO.ANSI.reset(),
  #          " to see all available apps"
  #        ]}
  #     end
  #   end
  # end
end
