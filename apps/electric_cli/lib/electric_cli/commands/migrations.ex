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
          flags: merge_flags(local_flags()),
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

          ## Examples

          To revert a migration by name:

              electric migrations revert NAME

          Or revert all of your local migrations to match the migrations on
          the server:

          electric migrations revert --all
          """,
          args: [
            migration_name: [
              value_name: "NAME",
              help: "Name of the migration",
              required: false,
              parser: :string
            ]
          ],
          options: merge_options(env_options()),
          flags:
            merge_flags(
              [
                all: [
                  long: "--all",
                  help:
                    "Revert all local migrations and replace with migrations from the server.",
                  required: false
                ],
                force: [
                  long: "--force",
                  help: "Force revert the named migration.",
                  required: false
                ]
              ] ++
                local_flags()
            )
        ]
      ]
    ]
  end

  def list(%{options: %{env: env, root: root}, flags: %{local: local}}) do
    with :ok <- Session.require_auth(local_stack?: local),
         {:ok, %Config{} = config} <- Config.load(root),
         {:ok, %Environment{} = environment} <- Config.target_environment(config, env) do
      Progress.run("Listing migrations", fn ->
        case Migrations.list_migrations(config, environment) do
          {:ok, {:results, rows, headings}, _mismatched} ->
            {:results, rows, headings}

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

  def revert(%{args: args, flags: %{local: local} = flags, options: %{env: env, root: root}}) do
    with :ok <- Session.require_auth(local_stack?: local),
         {:ok, %Config{} = config} <- Config.load(root),
         {:ok, %Environment{} = environment} <- Config.target_environment(config, env) do
      case {args, flags} do
        {%{migration_name: name}, %{all: false}} when is_binary(name) and name != "" ->
          Progress.run("Reverting migration", fn ->
            case Migrations.revert_migration(config, environment, name, flags.force) do
              :ok ->
                {:success, "Migration reverted successfully"}

              {:ok, warnings} ->
                {:success, Util.format_messages("warnings", warnings)}

              {:error, errors} when is_list(errors) or is_binary(errors) ->
                {:error, Util.format_messages("errors", errors)}

              alt ->
                alt
            end
          end)

        {%{migration_name: nil}, %{all: true}} ->
          Progress.run("Reverting all migrations", fn ->
            case Migrations.sync_down_migrations(config, environment) do
              :ok ->
                {:success, "Migrations reverted successfully"}

              {:ok, warnings} ->
                {:success, Util.format_messages("warnings", warnings)}

              {:error, errors} when is_list(errors) or is_binary(errors) ->
                {:error, Util.format_messages("errors", errors)}

              alt ->
                alt
            end
          end)

        _ ->
          {:error, "You must specify a migration NAME or use the --all flag."}
      end
    end
  end
end
