defmodule ElectricCli.Commands.Config.Init do
  use ElectricCli, :command
  import ElectricCli.Util, only: [verbose: 1]
  alias ElectricCli.Config

  def about() do
    """
    Initializes a new ElectricSQL application configuration.

    Creates a new file `electric.json` in either your current working directory or the directory
    specified by the `--dir` argument, that contains the application id of the current project
    along with a default environment and location of the (default) migrations folder.

    The APP_ID you give should be the slug of the app previous created in the web console.

    Once initialized, further invocations of the `electric` CLI will use the values in this
    configuration as defaults for all commands.
    """
  end

  @options [
    path: [
      value_name: "PATH",
      short: "-d",
      long: "--dir",
      parser: :string,
      help: "Project root directory",
      default: "."
    ]
  ]

  def spec do
    [
      name: "init",
      about: about(),
      flags:
        merge_flags(
          no_verify: [
            long: "--no-verify",
            help: "Don't verify app name against the console",
            required: false
          ]
        ),
      options: @options ++ migrations_options("./migrations") ++ env_options(),
      args: [
        app: [
          parser: :string,
          required: true,
          help:
            "Application identifier (required). Generated when you create an application in the console.",
          value_name: "APP"
        ]
      ]
    ]
  end

  def init(%Optimus.ParseResult{args: args} = opts) do
    root = root(opts)

    verbose("Setting application to '#{args.app}'")

    {:ok, env} = Map.fetch(opts.options, :env)

    verbose("Setting environment to '#{env}'")

    migrations_dir = opts.options.migrations_dir

    verbose("Setting migrations directory to '#{migrations_dir}'")
    verbose("Initialising migrations")

    config =
      Config.new(
        root: root,
        app: args.app,
        migrations_dir: migrations_dir,
        env: env
      )

    with {:ok, path} <- Config.init(config, opts.flags.no_verify) do
      verbose("Written electric configuration to '#{path}'")

      settings =
        config
        |> Map.from_struct()
        |> Enum.map(fn {k, v} ->
          ["\n", :white, "- ", to_string(k), :reset, ": ", :green, v, :reset]
        end)

      {:success, ["ElectricSQL configuration written to '#{path}'\n", :reset, settings]}
    end
  end

  defp root(%{options: options}) do
    Path.expand(options.path)
  end
end
