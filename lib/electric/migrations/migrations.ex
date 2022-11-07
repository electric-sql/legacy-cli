defmodule Electric.Migrations do
  @moduledoc """
  The `Migrations` context.
  Munges sql migrations and uploads them to the server
  """

  @migration_file_name "migration.sql"
  @manifest_file_name "manifest.json"
  @bundle_file_name "manifest.bundle.json"
  @js_bundle_file_name "index.js"
  @migration_template EEx.compile_file("lib/electric/migrations/templates/migration.sql.eex")
  @satellite_template EEx.compile_file("lib/electric/migrations/templates/satellite.sql.eex")
  @bundle_template EEx.compile_file("lib/electric/migrations/templates/index.js.eex")

  @type body_style() :: :none | :text | :list

  @doc """
  Creates the migrations folder and adds in initial migration to it.
  optional argument:
  - :dir where to create the migration rather than the current working directory
  """
  def init_migrations(options) do
    migrations_folder =
      case root_directory = Map.get(options, :dir) do
        nil ->
          "migrations"

        _ ->
          if Path.basename(root_directory) == "migrations" do
            root_directory
          else
            Path.join(root_directory, "migrations")
          end
      end

    if File.exists?(migrations_folder) do
      {:error, ["Migrations folder at #{migrations_folder} already exists."]}
    else
      File.mkdir_p!(migrations_folder)
      add_migration(migrations_folder, "init")
    end
  end

  @doc """
  Adds a new migration to the existing set of migrations.
  optional arguments:
  - :migrations a folder of migrations to add too if not using one in the cwd, must be called "migrations"
  """
  def new_migration(migration_name, opts) do
    case check_migrations_folder(opts) do
      {:ok, migrations_folder} ->
        add_migration(migrations_folder, migration_name)

      {:error, errors} ->
        {:error, errors}
    end
  end

  @doc """
  For every migration in the migrations folder creates a new file called satellite.sql, which is a copy of migration.sql
  but with all the triggers added for the schema up to this point
  optional arguments:
  - :migrations a folder of migrations to add too if not using one in the cwd, must be called "migrations"
  flags:
  - :manifest will also create a file called manifest.json in the migrations folder listing all migrations
  - :bundle will also create a index.js file in the migrations folder which exports a js object containing all the migrations
  """
  def build_migrations(flags, options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, folder} <- check_migrations_folder(options),
         {:ok, warnings} <-
           folder |> ordered_migrations() |> add_triggers_to_migrations(template),
         :ok <- optionally_write(&write_js_bundle/1, folder, flags[:bundle]),
         :ok <- optionally_write(&write_json_bundle/1, folder, flags[:json]),
         :ok <- optionally_write(&write_manifest/1, folder, flags[:manifest]) do
      if length(warnings) > 0 do
        {:ok, warnings}
      else
        {:ok, nil}
      end
    else
      {:error, errors} ->
        {:error, errors}
    end
  end

  defp optionally_write(_func, _folder, flag) when flag !== true do
    :ok
  end

  defp optionally_write(func, folder, _flag) do
    func.(folder)
  end

  @doc """
  Does nothing yet
  """
  def sync_migrations(db_id, options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, folder} <- check_migrations_folder(options),
         {:ok, warnings} <-
           folder |> ordered_migrations() |> add_triggers_to_migrations(template),
         migrations <- all_migrations_as_maps(folder, :text),
         {:ok, _msg} <-
           Electric.Migrations.Sync.sync_migrations(db_id, %{"migrations" => migrations}) do
      if length(warnings) > 0 do
        {:ok, warnings}
      else
        {:ok, nil}
      end
    else
      {:error, errors} ->
        {:error, errors}
    end
  end

  defp check_migrations_folder(options) do
    migrations_folder = Map.get(options, :dir, "migrations")

    if not File.exists?(migrations_folder) do
      {:error, ["Couldn't find the migrations folder at #{migrations_folder}"]}
    else
      if Path.basename(migrations_folder) == "migrations" do
        {:ok, migrations_folder}
      else
        #        IO.inspect(migrations_folder)
        {:error, ["The migrations folder must be called \"migrations\""]}
      end
    end
  end

  defp add_migration(migrations_folder, migration_title) do
    name =
      String.downcase(migration_title)
      |> String.replace(~r/[\/\*"\\\[\]:\;\|,\.]/, "_")
      |> String.slice(0..40)

    ts = System.os_time(:second)
    migration_name = "#{ts}_#{name}"
    migration_folder = Path.join(migrations_folder, migration_name)
    File.mkdir_p!(migration_folder)

    {body, _bindings} =
      Code.eval_quoted(@migration_template,
        title: migration_title,
        name: migration_name
      )

    migration_file_path = Path.join([migration_folder, @migration_file_name])
    File.write!(migration_file_path, body)
    {:ok, nil}
  end

  def get_template() do
    @satellite_template
  end

  @doc false
  def write_manifest(src_folder) do
    manifest_path = Path.join(src_folder, @manifest_file_name)
    manifest = create_bundle(src_folder, :none)

    if File.exists?(manifest_path) do
      File.rm(manifest_path)
    end

    File.write(manifest_path, manifest)
  end

  @doc false
  def write_json_bundle(src_folder) do
    migrations = create_bundle(src_folder, :text)
    bundle_path = Path.join(src_folder, @bundle_file_name)

    if File.exists?(bundle_path) do
      File.rm(bundle_path)
    end

    File.write(bundle_path, migrations)
  end

  @doc false
  def write_js_bundle(src_folder) do
    migrations = create_bundle(src_folder, :list)
    {result, _bindings} = Code.eval_quoted(@bundle_template, migrations: migrations)
    bundle_path = Path.join(src_folder, @js_bundle_file_name)

    if File.exists?(bundle_path) do
      File.rm(bundle_path)
    end

    File.write!(bundle_path, result)
  end

  defp ordered_migrations(src_folder) do
    sql_file_paths = Path.join([src_folder, "*", @migration_file_name]) |> Path.wildcard()

    migration_names =
      for file_path <- sql_file_paths do
        Path.dirname(file_path) |> Path.basename()
      end

    for migration_name <- Enum.sort(migration_names) do
      migration = %Electric.Migration{name: migration_name, src_folder: src_folder}

      case Electric.Migration.get_original_metadata(migration) do
        {:error, _} -> migration
        metadata -> %{migration | title: metadata["title"]}
      end
    end
  end

  defp create_bundle(src_folder, body_style) do
    migrations = all_migrations_as_maps(src_folder, body_style)
    Jason.encode!(%{"migrations" => migrations}) |> Jason.Formatter.pretty_print()
  end

  defp all_migrations_as_maps(src_folder, body_style) do
    for migration <- ordered_migrations(src_folder) do
      Electric.Migration.as_json_map(migration, body_style)
    end
  end

  defp calc_hash(with_triggers) do
    sha = :crypto.hash(:sha256, with_triggers)
    base16 = Base.encode16(sha)
    String.downcase(base16)
  end

  defp add_triggers_to_migrations(ordered_migrations, template) do
    read_migrations =
      for migration <- ordered_migrations do
        Electric.Migration.ensure_original_body(migration)
      end

    {status, message} =
      1..length(read_migrations)
      |> Enum.map(&Enum.take(read_migrations, &1))
      |> Enum.reduce_while({:ok, []}, fn subset, {_status, messages} ->
        case add_triggers_to_migration(subset, template) do
          {:ok, nil} ->
            {:cont, {:ok, messages}}

          {:ok, warnings} ->
            {:cont, {:ok, messages ++ warnings}}

          {:error, errors} ->
            {:halt, {:error, errors}}
        end
      end)

    if message == "" do
      {status, "Migrations built"}
    else
      {status, message}
    end
  end

  def strip_comments(sql) do
    String.replace(sql, ~r/--[^\n]*(?:\z|\n)/, "\n")
    |> String.replace(~r/\/\*[\s\S]*?(?:\z|\*\/)/, "\n")
  end

  @doc false
  def add_triggers_to_migration(migration_set, template) do
    migration = List.last(migration_set)

    hash = strip_comments(migration.original_body) |> calc_hash()

    case Electric.Migrations.Triggers.add_triggers_to_last_migration(migration_set, template) do
      {:error, reasons} ->
        {:error, reasons}

      {with_triggers, warnings} ->
        migrations =
          for migration <- migration_set do
            %{original_body: migration.original_body, name: migration.name}
          end

        satellite_file_path = Electric.Migration.satellite_file_path(migration)

        warnings =
          if File.exists?(satellite_file_path) do
            metadata = Electric.Migration.get_satellite_metadata(migration)

            if metadata["sha256"] != hash do
              File.rm(satellite_file_path)
              ["The migration #{migration.name} has been modified." | warnings]
            else
              warnings
            end
          else
            warnings
          end

        if not File.exists?(satellite_file_path) do
          header =
            case Electric.Migration.get_original_metadata(migration) do
              {:error, _reason} ->
                Electric.Migration.file_header(migration, hash, nil)

              existing_metadata ->
                Electric.Migration.file_header(migration, hash, existing_metadata["title"])
            end

          File.write!(satellite_file_path, header <> with_triggers)
          {:ok, warnings}
        else
          {:ok, warnings}
        end
    end
  end
end
