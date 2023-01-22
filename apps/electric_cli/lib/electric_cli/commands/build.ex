defmodule ElectricCli.Commands.Build do
  use ElectricCli, :command

  alias ElectricCli.Config.Environment
  alias ElectricCli.Core

  def about() do
    """
    Build your config and migrations.

    You must build your config and migrations before syncing up to the backend
    and importing into your application code.

    By default this will build for your `defaultEnv`. If you want to target
    a different one use `--env ENV`.

    Examples:
        electric build
        electric build --env ENV
    """
  end

  def spec do
    [
      name: "build",
      about: about(),
      flags:
        merge_flags(
          postgres: [
            long: "--postgres",
            short: "-p",
            help: "Generate PostgresSQL migration files locally when building",
            required: false
          ],
          satellite: [
            long: "--satellite",
            short: "-s",
            help: "Generate Satellite (SQLite) migration files locally when building",
            required: false
          ]
        ),
      options: merge_options(env_options())
    ]
  end

  def build(%{options: %{env: env, root: root}, flags: flags}) do
    with {:ok, %Config{} = config} <- Config.load(root),
         {:ok, %Environment{} = environment} <- Config.target_environment(config, env) do
      Progress.run("Building", fn ->
        case Core.build(config, environment, flags.postgres, flags.satellite) do
          :ok ->
            {:success, "Built successfully"}

          {:warning, warnings} ->
            {:success, Util.format_messages("warnings", warnings)}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}
        end
      end)
    end
  end
end
