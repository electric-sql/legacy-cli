defmodule ElectricCli.Commands.Config.Update do
  use ElectricCli, :command
  import ElectricCli.Util, only: [verbose: 1]

  alias ElectricCli.Config
  alias ElectricCli.Migrations

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

  def about do
    """
    Updates your configuration.

    Updates the `app`, `env` and `migrations` directory in your `electric.json`.
    """
  end

  def spec do
    [
      name: "update",
      about: about(),
      flags:
        merge_flags(
          no_verify: [
            long: "--no-verify",
            help: "Don't verify app name against the console",
            required: false
          ]
        ),
      options:
        @options ++
          app_flags(false) ++
          env_options() ++
          migrations_options("./migrations")
    ]
  end

  def update(%Optimus.ParseResult{options: options, flags: flags}) do
    root = Path.expand(options.path)

    with {:ok, config} <- Config.load(root) do
      attrs =
        options
        |> Util.take_unless_nil([:app, :env, :migrations_dir])
        |> Map.put(:root, root)

      case config |> Map.merge(attrs) |> Config.new() do
        ^config ->
          {:success, ["Nothing to update"]}

        config ->
          verbose("Patching migrations manifest")
          Migrations.update_app(config.app, options)

          verbose("Updating configuration")

          with {:ok, _} <- Config.init(config, flags.no_verify) do
            {:success, ["Configuration updated successfully"]}
          end
      end
    end
  end
end
