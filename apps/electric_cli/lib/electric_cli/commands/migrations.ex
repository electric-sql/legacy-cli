defmodule ElectricCli.Commands.Migrations do
  @moduledoc """
  The `Migrations` command.


  # Initialise a new set of migrations and the initial migration file
  electric migrations init --migrations-dir ./local/path/to/migrations

  # Generate an new empty migration file.
  electric migrations new :migration_name --migrations-dir ./local/path/to/migrations

  # Read the migrations source folder. Validate.
  # Create a output folder with patched files
  # containing triggers.
  electric migrations build --migrations-dir ./local/path/to/migrations --manifest --bundle

  # Sync the migrations with the console, so that
  # they can be applied to PG and propagated to
  # satellite clients.
  electric migrations push :database_id --migrations-dir ./local/path/to/migrations
  """
  use ElectricCli, :command

  alias ElectricCli.Config

  @migration_title [
    migration_title: [
      value_name: "MIGRATION_TITLE",
      help: "Title of a new migration",
      required: true,
      parser: :string
    ]
  ]

  @migration_name [
    migration_name: [
      value_name: "MIGRATION_NAME",
      help: "The name of an existing migration",
      required: true,
      parser: :string
    ]
  ]

  @postgres [
    postgres: [
      long: "--postgres",
      short: "-p",
      help: "Also generate PostgresSQL when building",
      required: false
    ]
  ]

  @satellite [
    satellite: [
      long: "--satellite",
      short: "-s",
      help: "Also generate satellite SQL when building",
      required: false
    ]
  ]

  def spec do
    [
      name: "migrations",
      about: "Manage database schema migrations",
      subcommands: [
        new: [
          name: "new",
          about: """
          Creates a new migration.

          MIGRATION_TITLE should be a short human readable description of the new migration.

          This adds a new migration to the 'migrations' folder with a name automatically derived from the current
          time in UTC and the given title.

          """,
          args: @migration_title,
          options: config_options() ++ migrations_options(),
          flags: default_flags()
        ],
        build: [
          name: "build",
          about: """
          Builds a javascript file at `dist/index.js`.

          This file bundles all your migrations with ElectricSQL's added DDL and some additional metadata.

          The metadata in this file will have a `"env": "local" to indicate the it was built from your local files
          rather that one of the named app environments.

          Add this file to your mobile or web project to configure your SQLite database.
          """,
          options: config_options() ++ migrations_options(),
          flags: default_flags() |> Keyword.merge(@postgres) |> Keyword.merge(@satellite)
        ],
        sync: [
          name: "sync",
          about: """
          Synchronizes migrations with the server.

          Synchronises changes you have made to migration SQL files in your local `migrations` folder up to the ElectricSQL servers,
          and builds a new javascript file at `dist/index.js` that matches the newly synchronised set of migrations.

          The metadata in this file will have a `"env": ENVIRONMENT to indicate that it was built directly from and matches
          the named app environment.

          By default this will sync to the `default` environment for your app. If you want to use a different one give its name
          with `--env ENVIRONMENT`

          If the app environment on our servers already has a migration with the same name but different sha256 then this
          synchronization will fail because a migration cannot be modified once it has been applied.
          If this happens you have two options, either revert the local changes you have made to the conflicted migration using
          the `revert` command below or, if you are working in a development environment that you are happy to reset,
          you can reset the whole environment's DB using the web control panel.

          Also if a migration has a name that is lower in sort order than one already applied on the server this sync will fail.
          """,
          options: config_options() ++ migrations_options() ++ env_options(),
          flags: default_flags()
        ],
        #        apply: [
        #          name: "apply",
        #          about: """
        #          Applies all migrations
        #          """,
        #          options: config_options() ++ migrations_options(),
        #          flags: default_flags()
        #        ],
        list: [
          name: "list",
          about: """
          Lists all migrations.

          Shows a list of all the migrations and their status in every env in the app.
          """,
          options: config_options() ++ migrations_options(),
          flags: default_flags()
        ],
        revert: [
          name: "revert",
          about: """
          Copies the named migration from the server to replace the local one.
          """,
          args: @migration_name,
          options: config_options() ++ migrations_options() ++ env_options(),
          flags: default_flags()
        ]
      ]
    ]
  end

  def format_messages(type_of_message, messages) when is_list(messages) do
    "There were #{length(messages)} #{type_of_message}:\n" <> Enum.join(messages, "\n")
  end

  def format_messages(type_of_message, messages) do
    "There was 1 #{type_of_message}:\n" <> messages
  end

  def init(_cmd) do
    {:error, "Please run `electric init` to initialize your application"}
  end

  def new(%{args: args, flags: _flags, options: options, unknown: _unknown}) do
    with {:ok, config} <- Config.load(options.root) do
      options = Config.merge(config, options)

      ElectricCli.Progress.run("Creating new migration", fn ->
        case ElectricCli.Migrations.new_migration(args.migration_title, options) do
          {:ok, migration_file_path} ->
            {:success, "New migration created at:\n#{migration_file_path}"}

          {:error, errors} ->
            {:error, format_messages("errors", errors)}
        end
      end)
    end
  end

  def build(%{options: options, flags: flags, unknown: _unknown}) do
    with {:ok, config} <- Config.load(options.root) do
      options = Config.merge(config, options)

      Progress.run("Building satellite migrations", fn ->
        case ElectricCli.Migrations.build_migrations(options, flags) do
          {:ok, nil} ->
            {:success, "Migrations built successfully"}

          {:ok, warnings} ->
            #        IO.inspect(warnings)
            {:success, format_messages("warnings", warnings)}

          {:error, errors} ->
            {:error, format_messages("errors", errors)}
        end
      end)
    end
  end

  #  def apply(%{options: options, unknown: _unknown}) do
  #    env = Map.get(options, :env, "default")
  #
  #    Progress.run("Applying satellite migrations", fn ->
  #      case ElectricCli.Migrations.apply_migrations(env, options) do
  #        {:ok, nil} ->
  #          {:success, "Migrations applied successfully"}
  #        {:ok, warnings} ->
  #          #        IO.inspect(warnings)
  #          {:success, format_messages("warnings", warnings)}
  #
  #        {:error, errors} ->
  #          {:error, format_messages("errors", errors)}
  #      end
  #    end)
  #  end

  def sync(%{args: _args, flags: _flags, options: options, unknown: _unknown}) do
    with {:ok, config} <- Config.load(options.root),
         :ok <- Session.require_auth() do
      options = Config.merge(config, options)

      Progress.run("Synchronizing migrations", false, fn ->
        case ElectricCli.Migrations.sync_migrations(options.env, options) do
          {:ok, nil} ->
            {:success, "Migrations synchronized with server successfully"}

          {:ok, warnings} ->
            #        IO.inspect(warnings)
            {:success, format_messages("warnings", warnings)}

          {:error, errors} ->
            {:error, format_messages("errors", errors)}

          error ->
            error
        end
      end)
    end
  end

  def list(%{options: options}) do
    with {:ok, config} <- Config.load(options.root) do
      options = Config.merge(config, options)

      case ElectricCli.Migrations.list_migrations(options) do
        {:ok, listing, _mismatched} ->
          {:success, listing}

        {:error, errors} ->
          {:error, format_messages("errors", errors)}
      end
    end
  end

  def app(%{args: %{app: _app_id}, options: _options}) do
    # TODO: implement config app command
    {:error, "Use `electric config app` to set the app id"}
    # case ElectricCli.Migrations.update_app_id(app_id, options) do
    #   {:ok, _} ->
    #     {:success, "Changed to using app #{app_id}"}

    #   {:error, errors} ->
    #     {:error, format_messages("errors", errors)}
    # end
  end

  def revert(%{args: %{migration_name: migration_name}, options: options}) do
    with {:ok, config} <- Config.load(options.root) do
      options = Config.merge(config, options)

      Progress.run("Reverting migration", fn ->
        case ElectricCli.Migrations.revert_migration(options.env, migration_name, options) do
          {:ok, nil} ->
            {:success, "Migration reverted successfully"}

          {:ok, warnings} ->
            #        IO.inspect(warnings)
            {:success, format_messages("warnings", warnings)}

          {:error, errors} ->
            {:error, format_messages("errors", errors)}
        end
      end)
    end
  end
end
