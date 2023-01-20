defmodule ElectricCli.Commands.Migrations do
  @moduledoc """
  The `Migrations` command.
  """
  use ElectricCli, :command

  alias ElectricCli.Config.Environment
  alias ElectricCli.Migrations

  def spec do
    [
      name: "migrations",
      about: "Manage DDL schema migrations.",
      subcommands: [
        new: [
          name: "new",
          about: """
          Create a new migration.

          NAME should be a short human readable description of the new migration,
          such as "create items" or "add foo to bars".

          This adds a new migration to the 'migrations' folder with a name that's
          automatically derived from the current time in UTC and the given title.
          """,
          args: [
            migration_name: [
              value_name: "NAME",
              help: "Name of the new migration",
              required: true,
              parser: :string
            ]
          ],
          flags: default_flags(),
          options: default_options()
        ],
        build: [
          name: "build",
          about: """
          Build your migrations.

          You must build your migrations before importing into your local app and
          before syncing up to the backend.

          By default this will build for your `defaultEnv`. If you want to target
          a different one use `--env ENV`.
          """,
          options: merge_options(env_options()),
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
            )
        ],
        sync: [
          name: "sync",
          about: """
          Sync migrations with the backend.

          This synchronises your local changes up to your ElectricSQL sync service
          and builds a new javascript file at `:output_dir/:app/:env/index.js` that
          matches the newly synchronised set of migrations.

          The metadata in this file will have a `"env": ENVIRONMENT to indicate that
          it was built directly from and matches the migrations applied to the target
          app environment.

          By default this will sync to your `defaultEnv`. If you want to target a
          different one use `--env ENV`.

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
          """,
          options: merge_options(env_options()),
          flags: default_flags()
        ],
        # apply: [
        #   name: "apply",
        #   about: """
        #   Applies all migrations
        #   """,
        #   flags: default_flags()
        # ],
        list: [
          name: "list",
          about: """
          Lists all migrations.

          Shows a list of all the migrations and their status in every env in the app.
          """,
          flags: default_flags(),
          options: default_options()
        ],
        revert: [
          name: "revert",
          about: """
          Copies the named migration from the server to replace the local one.

          Uses your `defaultEnv` unless you specify `--env ENV`.
          """,
          args: [
            migration_name: [
              value_name: "NAME",
              help: "The name of the existing migration",
              required: true,
              parser: :string
            ]
          ],
          options: merge_options(env_options()),
          flags: default_flags()
        ]
      ]
    ]
  end

  def new(%{args: args, options: %{root: root}}) do
    name = args.migration_name

    with {:ok, %Config{} = config} <- Config.load(root) do
      Progress.run("Creating new migration", fn ->
        case Migrations.new_migration(name, config) do
          {:ok, relative_file_path} ->
            {:success, "New migration created at:\n#{relative_file_path}"}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}
        end
      end)
    end
  end

  def build(%{
        options: %{env: env, root: root},
        flags: %{postgres: postgres_flag, satellite: satellite_flag}
      }) do
    with {:ok, %Config{} = config} <- Config.load(root),
         {:ok, env_atom} <- Config.existing_env_atom(config, env) do
      Progress.run("Building migrations", fn ->
        case Migrations.build_migrations(config, env_atom, postgres_flag, satellite_flag) do
          {:ok, nil} ->
            {:success, "Migrations built successfully"}

          {:ok, warnings} ->
            {:success, Util.format_messages("warnings", warnings)}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}
        end
      end)
    end
  end

  # def apply(%{options: %{env: env, root: root}}) do
  #   with {:ok, %Config{} = config} <- Config.load(root),
  #        {:ok, %Environment{} = environment} <- Config.target_environment(config, env) do
  #     Progress.run("Applying migrations", fn ->
  #       case Migrations.apply_migrations(config, environment) do
  #         {:ok, nil} ->
  #           {:success, "Migrations applied successfully"}
  #         {:ok, warnings} ->
  #           {:success, Util.format_messages("warnings", warnings)}
  #         {:error, errors} ->
  #           {:error, Util.format_messages("errors", errors)}
  #       end
  #     end)
  #   end
  # end

  def sync(%{options: %{env: env, root: root}}) do
    with {:ok, %Config{} = config} <- Config.load(root),
         {:ok, %Environment{} = environment} <- Config.target_environment(config, env),
         :ok <- Session.require_auth() do
      Progress.run("Sync migrations", false, fn ->
        case Migrations.sync_migrations(config, environment) do
          {:ok, nil} ->
            {:success, "Migrations synced successfully"}

          {:ok, warnings} ->
            {:success, Util.format_messages("warnings", warnings)}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}

          error ->
            error
        end
      end)
    end
  end

  def list(%{options: %{root: root}}) do
    with {:ok, %Config{} = config} <- Config.load(root) do
      Progress.run("Listing migrations", fn ->
        case Migrations.list_migrations(config) do
          {:ok, listing, _mismatched} ->
            {:success, listing}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}
        end
      end)
    end
  end

  def revert(%{options: %{env: env, migration_name: migration_name, root: root}}) do
    with {:ok, %Config{} = config} <- Config.load(root),
         {:ok, %Environment{} = environment} <- Config.target_environment(config, env) do
      Progress.run("Reverting migration", fn ->
        case Migrations.revert_migration(config, environment, migration_name) do
          {:ok, nil} ->
            {:success, "Migration reverted successfully"}

          {:ok, warnings} ->
            {:success, Util.format_messages("warnings", warnings)}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}
        end
      end)
    end
  end
end
