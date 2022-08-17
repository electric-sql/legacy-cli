defmodule Electric.Commands.Migrations do
  @moduledoc """
  The `Migrations` command.

  # Generate an empty migration file.
  electric migrations generate --source-path ./local/path/to/folder

  # Are the migrations OK? what are the issues,
  # e.g.: "you're using a sequential ID".
  electric migrations validate --source-path ./local/path/to/folder

  # Read the migrations source folder. Validate.
  # Create a output folder with patched files
  # containing triggers.
  electric migrations build --source-path ./local/path/to/folder --dist-path ./local/path/to/dist

  # Sync the migrations with the console, so that
  # they can be applied to PG and propagated to
  # satellite clients.
  electric migrations push :database_uuid --dist-path ./local/path/to/folder
  """
  use Electric, :command

  @database_id [
    database_id: [
      value_name: "DATABASE_ID",
      help: "Database ID (e.g.: from `electric databases list`)",
      required: true,
      parser: :string
    ]
  ]

  @dist_dir [
    dist_dir: [
      value_name: "DIST_DIR",
      short: "-d",
      long: "--dist-dir",
      help: "Dist directory for the build migration files.",
      parser: :string,
      default: "./migrations/src"
    ]
  ]

  @source_dir [
    source_dir: [
      value_name: "SOURCE_DIR",
      short: "-s",
      long: "--source-dir",
      help: "Source directory where the migration files live.",
      parser: :string,
      default: "./migrations/dist"
    ]
  ]

  @source_file [
    source_file: [
      value_name: "SOURCE_FILE",
      short: "-f",
      long: "--source-file",
      help: "Path to a specific migration file.",
      parser: :string,
      required: false
    ]
  ]

  def spec do
    [
      name: "migrations",
      about: "Manage database schema migrations",
      subcommands: [
        list: [
          name: "list",
          about: """
          List the migrations for a database.

          List all the migrations currently pushed to a database.
          """,
          args: @database_id,
          flags: default_flags()
        ],
        generate: [
          name: "generate",
          about: """
          Generate an empty migration file.

          Ensures the migration file has the right filename prefix and metadata.
          """,
          options: @source_dir,
          flags: default_flags()
        ],
        validate: [
          name: "validate",
          about: """
          Validate your migrations.

          Either validate all migrations in a folder, or a specific migration file.
          """,
          options:
            Keyword.merge(
              @source_dir,
              @source_file
            ),
          flags: default_flags()
        ],
        build: [
          name: "build",
          about: """
          Build migrations dist folder.

          Read migrations from SOURCE_DIR. Validate and patch ready for
          application to SQLite. Write output files to the DIST_DIR.

          You must build migrations before building into your local app
          and / or deploying to your cloud database.
          """,
          options:
            Keyword.merge(
              @source_dir,
              @dist_dir
            ),
          flags: default_flags()
        ],
        deploy: [
          name: "deploy",
          about: """
          Deploy migrations to your cloud database.

          Pushes your DIST_DIR of built migrations to your cloud database,
          so they're applied to your cloud Postgres and propagated out to
          your live client applications.
          """,
          args: @database_id,
          options: @dist_dir,
          flags: default_flags()
        ]
      ]
    ]
  end

  def list(%{args: %{database_id: database_id}}) do
    path = "databases/#{database_id}/migrations"

    case Client.get(path) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:results, data}

      {:ok, %Req.Response{}} ->
        {:error, "bad request"}

      {:error, _exception} ->
        {:error, "failed to connect"}
    end
  end

  def generate(%{options: %{source_dir: source_dir}}) do
    # XXX
    IO.inspect({:generate, source_dir})
  end

  def validate(%{options: %{source_file: source_file}}) when is_binary(source_file) do
    # XXX
    IO.inspect({:validate, :file, source_file})
  end

  def validate(%{options: %{source_dir: source_dir}}) do
    # XXX
    IO.inspect({:validate, :dir, source_dir})
  end

  def build(%{options: %{source_dir: source_dir, dist_dir: dist_dir}}) do
    # XXX
    IO.inspect({:build, source_dir, dist_dir})
  end

  def deploy(%{args: %{database_id: database_id}, options: %{dist_dir: dist_dir}}) do
    path = "databases/#{database_id}/migrations"

    # XXX
    data = :NotImplemented
    IO.inspect({:deploy, data, dist_dir})

    case Client.post(path, data) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:results, data}

      # XXX probably need to handle the response more carefully here.
      # {:ok, %Req.Response{}} ->
      #   {:error, "bad request"}

      {:error, _exception} ->
        {:error, "failed to connect"}
    end
  end
end
