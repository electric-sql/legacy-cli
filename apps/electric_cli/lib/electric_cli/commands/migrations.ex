defmodule ElectricCli.Commands.Migrations do
  @moduledoc """
  The `Migrations` command.
  """
  use ElectricCli, :command

  alias ElectricCli.Config.Environment
  alias ElectricCli.Migrations

  @migration_arg [
    migration_name: [
      value_name: "NAME",
      help: "Name of the migration",
      required: true,
      parser: :string
    ]
  ]

  def spec do
    [
      name: "migrations",
      about: "Manage DDL schema migrations.",
      subcommands: [
        list: [
          name: "list",
          about: """
          Lists migrations.

          Shows a list of all the migrations for the current app and
          their build and sync status.

          Uses your `defaultEnv` unless you specify `--env ENV`.
          """,
          flags: default_flags(),
          options: merge_options(env_options())
        ],
        new: [
          name: "new",
          about: """
          Create a new migration.

          NAME should be a short human readable description of the new migration,
          such as "create items" or "add foo to bars".

          This adds a new migration to the 'migrations' folder with a name that's
          automatically derived from the current time in UTC and the given title.
          """,
          args: @migration_arg,
          flags: default_flags(),
          options: default_options()
        ],
        revert: [
          name: "revert",
          about: """
          Copies the named migration from the server to replace the local one.

          Uses your `defaultEnv` unless you specify `--env ENV`.
          """,
          args: @migration_arg,
          options: merge_options(env_options()),
          flags: default_flags()
        ]
      ]
    ]
  end

  def list(%{options: %{env: env, root: root}}) do
    with {:ok, %Config{} = config} <- Config.load(root),
         {:ok, %Environment{} = environment} <- Config.target_environment(config, env) do
      Progress.run("Listing migrations", fn ->
        case Migrations.list_migrations(config, environment) do
          {:ok, listing, _mismatched} ->
            {:success, listing}

          {:error, errors} ->
            {:error, Util.format_messages("errors", errors)}
        end
      end)
    end
  end

  def new(%{args: args, options: %{root: root}}) do
    name = args.migration_name

    with {:ok, %Config{} = config} <- Config.load(root) do
      Progress.run("Creating new migration", fn ->
        case Migrations.new_migration(config, name) do
          {:ok, relative_file_path} ->
            {:success, "New migration created at:\n#{relative_file_path}"}

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
