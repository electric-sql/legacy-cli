defmodule Electric.Commands.Migrations do
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
  use Electric, :command

  @migration_name [
    migration_name: [
      value_name: "MIGRATION_NAME",
      help: "Name of a new migration",
      required: true,
      parser: :string
    ]
  ]

  @app [
    app: [
      value_name: "APP_SLUG",
      help: "Globally unique slug generated when you create an application",
      required: true,
      parser: :string
    ]
  ]

  @dir [
    dir: [
      value_name: "MIGRATIONS_DIR",
      short: "-d",
      long: "--dir",
      help: "Migrations directory where the migration files live.",
      parser: :string,
      default: "./migrations"
    ]
  ]

  @manifest [
    manifest: [
      long: "--manifest",
      short: "-m",
      help: "Create a json manifest when building",
      required: false
    ]
  ]

  @bundle [
    bundle: [
      long: "--bundle",
      short: "-b",
      help: "Create a js bundle of all migrations when building",
      required: false
    ]
  ]

  def spec do
    [
      name: "migrations",
      about: "Manage database schema migrations",
      subcommands: [
        init: [
          name: "init",
          about: """
           Initialises a new set of migrations and the initial migration file
          """,
          options: @dir,
          flags: default_flags()
        ],
        new: [
          name: "new",
          about: """
           Creates a new migration folder and file
          """,
          args: @migration_name,
          options: @dir,
          flags: default_flags()
        ],
        build: [
          name: "build",
          about: """
          Build migrations dist folder.

          Reads the migration.sql file in each migration folder and create a new satellite.sql next to it.

          You must build migrations before building into your local app
          and / or syncing to your cloud database.
          """,
          options: @dir,
          flags: default_flags() |> Keyword.merge(@manifest) |> Keyword.merge(@bundle)
        ],
        sync: [
          name: "sync",
          about: """
          Sync migrations to your cloud database.

          Pushes your built migrations to your cloud database,
          so they're applied to your cloud Postgres and propagated out to
          your live client applications.
          """,
          args: @app,
          options: @dir,
          flags: default_flags()
        ]
      ]
    ]
  end

  def list(%{args: %{database_id: database_id}}) do
    path = "databases/#{database_id}/migrations"

    result =
      Progress.run("Listing migrations", false, fn ->
        Client.get(path)
      end)

    case result do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:results, data}

      {:ok, %Req.Response{}} ->
        {:error, "bad request"}

      {:error, _exception} ->
        {:error, "failed to connect"}
    end
  end

  def format_messages(type_of_message, messages) when is_list(messages) do
    "There were #{length(messages)} #{type_of_message}:\n" <> Enum.join(messages, "\n")
  end

  def format_messages(type_of_message, messages) do
    "There was 1 #{type_of_message}:\n" <> messages
  end

  def init(%{args: _args, flags: _flags, options: options, unknown: _unknown}) do
    case Electric.Migrations.init_migrations(options) do
      {:ok, nil} ->
        {:success, "Migrations initialised"}

      {:error, errors} ->
        {:error, format_messages("errors", errors)}
    end
  end

  def new(%{args: args, flags: _flags, options: options, unknown: _unknown}) do
    case Electric.Migrations.new_migration(args.migration_name, options) do
      {:ok, nil} ->
        {:success, "New migration created"}

      {:error, errors} ->
        {:error, format_messages("errors", errors)}
    end
  end

  def build(%{args: _args, flags: flags, options: options, unknown: _unknown}) do
    case Electric.Migrations.build_migrations(flags, options) do
      {:ok, nil} ->
        {:success, "Migrations build successfully"}

      {:ok, warnings} ->
        #        IO.inspect(warnings)
        {:success, format_messages("warnings", warnings)}

      {:error, errors} ->
        {:error, format_messages("errors", errors)}
    end
  end

  def sync(%{args: %{app: app_name, env: environment}, options: options}) do
    case Electric.Migrations.sync_migrations(app_name, environment, options) do
      {:ok, nil} ->
        {:success, "Migrations synchronized with server successfully"}

      {:ok, warnings} ->
        #        IO.inspect(warnings)
        {:success, format_messages("warnings", warnings)}

      {:error, errors} ->
        {:error, format_messages("errors", errors)}
    end
  end
end
