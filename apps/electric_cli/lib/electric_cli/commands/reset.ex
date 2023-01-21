defmodule ElectricCli.Commands.Reset do
  use ElectricCli, :command

  alias ElectricCli.Config.Environment
  alias ElectricCli.Migrations

  def about() do
    """
    Reset your backend.

    Reset deletes and re-creates your database and sync service.
    This is sometimes useful when you want to reset the database
    schema that your backend is using, so that you can re-apply
    your migrations against a fresh database.

    THIS COMMAND CAUSES DATA LOSS. Never reset a production
    environment, unless you know *exactly* what you're doing.

    Examples:
        electric reset
        electric reset --env ENV

    Example reset, rebuild and resync to align your backend
    database schema with your local development environment:

        electric reset
        electric build
        electric sync

    """
  end

  def spec do
    [
      name: "reset",
      about: about(),
      flags:
        merge_flags(
          skip_confirmation: [
            long: "--skip-configuration",
            short: "-s",
            help: "Skip confirmation prompt (warning: DANGEROUS)",
            required: false
          ]
        ),
      options: merge_options(env_options())
    ]
  end

  def reset(%{options: %{env: env, root: root}, flags: %{skip_confirmation: skip_confirmation}}) do
    with {:ok, %Config{app: app} = config} <- Config.load(root),
         {:ok, %Environment{slug: env_slug}} <- Config.target_environment(config, env),
         true <- confirm_absolutely_sure(skip_confirmation, app, "#{env_slug}") do
      # Progress.run("Building migrations", fn ->
      #   case Migrations.build_migrations(config, env_atom, postgres_flag, satellite_flag) do
      #     {:ok, nil} ->
      #       {:success, "Migrations built successfully"}

      #     {:ok, warnings} ->
      #       {:success, Util.format_messages("warnings", warnings)}

      #     {:error, errors} ->
      #       {:error, Util.format_messages("errors", errors)}
      #   end
      # end)
    else
      false ->
        {:success, "Reset aborted."}

      alt ->
        alt
    end
  end

  defp confirm_absolutely_sure(true, _app, _env) do
    true
  end

  defp confirm_absolutely_sure(false, app, env) do
    """
    You're about to reset:

    - app: #{app}
    - env: #{env}

    THIS WILL CAUSE IRREVERSIBLE DATA LOSS.
    Are you sure you want to continue?

    [y/N]:
    """
    |> String.trim()
    |> Kernel.<>(" ")
    |> IO.gets()
    |> String.trim_leading()
    |> String.downcase()
    |> String.starts_with?("y")
  end
end
