defmodule ElectricCli.Commands.Sync do
  use ElectricCli, :command

  alias ElectricCli.Config.Environment
  alias ElectricCli.Core

  def about() do
    """
    Sync local migrations with the backend.

    This synchronises your local changes up to your ElectricSQL sync service
    and builds a new javascript file at `:output_dir/:app/:env/index.js` that
    matches the newly synchronised set of migrations.

    The metadata in this file will have a `"env": ENVIRONMENT to indicate that
    it was built directly from and matches the migrations applied to the target
    app environment.

    By default this will sync to your `defaultEnv`. If you want to target a
    different one use `--env ENV`.

    Examples:

        electric sync
        electric sync --env ENV

    Notes:

    If the app environment on your sync service already has a migration with the
    same name but different sha256 then this sync will fail because a migration
    cannot be modified once it has been applied.

    If this happens you have two options, either revert the local changes you've
    made to the conflicted migration using the `revert` command below. Or, if
    you're working in a development environment that you're happy to reset,
    you can reset the sync service using the console interface.

    The sync will also fail if the migration has a name that is lower in sort order
    than one already applied on the server.
    """
  end

  def spec do
    [
      name: "sync",
      about: about(),
      flags: default_flags(),
      options: merge_options(env_options())
    ]
  end

  def sync(%{options: %{env: env, root: root}}) do
    with :ok <- Session.require_auth(),
         {:ok, %Config{} = config} <- Config.load(root),
         {:ok, %Environment{} = environment} <- Config.target_environment(config, env) do
      Progress.run("Syncing", false, fn ->
        case Core.sync(config, environment) do
          {:ok, message} ->
            {:success, message}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}

          error ->
            error
        end
      end)
    end
  end
end
