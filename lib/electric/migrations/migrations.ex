defmodule Electric.Migrations do
  @moduledoc """
  The `Migrations` context.
  Munges sql migrations and uploads them to the server
  """

  import Electric.Util, only: [verbose: 1]

  @migration_file_name "migration.sql"
  @manifest_file_name "manifest.json"
  @postgres_file_name "postgres.sql"
  @satellite_file_name "satellite.sql"
  @js_bundle_file_name "index.js"
  @dist_folder_name "dist"
  @migration_template EEx.compile_file("lib/electric/migrations/templates/migration.sql.eex")
  @satellite_template EEx.compile_file("lib/electric/migrations/templates/satellite.sql.eex")
  @bundle_template EEx.compile_file("lib/electric/migrations/templates/index.js.eex")

  @type body_style() :: :none | :text | :list

  @doc """
  Creates the migrations folder and adds in initial migration to it.
  optional argument:
  - :dir where to create the migration rather than the current working directory
  """
  def init_migrations(app_id, options) do
    migrations_folder =
      case Map.get(options, :migrations_dir) do
        nil ->
          "migrations"

        path ->
          path
      end
      |> Path.expand()

    verbose("Using migrations directory #{migrations_folder}")

    unless File.exists?(migrations_folder) do
      verbose("Creating '#{migrations_folder}'")
      File.mkdir_p!(migrations_folder)
    end

    case init_migration_exists?(app_id, migrations_folder) do
      {:ok, false} ->
        add_migration(migrations_folder, "init", app_id)

      {:ok, true} ->
        {:ok, true}

      {:error, _reason} = error ->
        error
    end
  end

  defp init_migration_exists?(app_id, migrations_folder) do
    if File.exists?(Path.join(migrations_folder, @manifest_file_name)) do
      manifest = read_manifest(migrations_folder)

      if manifest["app_id"] == app_id do
        {:ok, Enum.any?(manifest["migrations"], fn m -> m["title"] == "init" end)}
      else
        {:error,
         "App ID of existing migrations ('#{manifest["app_id"]}') does not match new value: '#{app_id}'"}
      end
    else
      {:ok, false}
    end
  end

  def update_app_id(app_id, options) do
    with {:ok, src_folder} <- check_migrations_folder(options) do
      update_manifest_app_id(src_folder, app_id)
    end
  end

  @doc """
  Adds a new migration to the existing set of migrations.
  optional arguments:
  - :migrations a folder of migrations to add too if not using one in the cwd, must be called "migrations"
  """
  def new_migration(migration_name, options) do
    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, _app_id} <- check_app_id(src_folder) do
      add_migration(src_folder, migration_name)
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
  def build_migrations(options, flags) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, app_id} <- check_app_id(src_folder),
         {:ok, triggered_manifest, warnings} <-
           update_manifest(src_folder, template, flags[:satellite]),
         :ok <-
           optionally_write(&write_satellite/2, src_folder, triggered_manifest, flags[:satellite]),
         {:ok, postgres_manifest, _} = add_postgres_bodies(triggered_manifest, flags[:postgres]),
         :ok <-
           optionally_write(&write_postgres/2, src_folder, postgres_manifest, flags[:postgres]) do
      write_js_bundle(src_folder, triggered_manifest, app_id, "local")

      if length(warnings) > 0 do
        {:ok, warnings}
      else
        {:ok, nil}
      end
    end
  end

  @doc """
  Does nothing yet
  """
  def sync_migrations(environment, options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, app_id} <- check_app_id(src_folder),
         {:ok, updated_manifest, warnings} = update_manifest(src_folder, template),
         {:ok, _msg} <-
           Electric.Migrations.Sync.sync_migrations(app_id, environment, updated_manifest),
         {:ok, server_manifest} <-
           Electric.Migrations.Sync.get_migrations_from_server(app_id, environment, true),
         :ok <- write_js_bundle(src_folder, server_manifest, app_id, environment) do
      if length(warnings) > 0 do
        {:ok, warnings}
      else
        {:ok, nil}
      end
    end
  end

  def apply_migrations(environment, options) do
    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, app_id} <- check_app_id(src_folder) do
      Electric.Migrations.Sync.apply_all_migrations(app_id, environment)
    end
  end

  def list_migrations(options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, app_id} <- check_app_id(src_folder),
         {:ok, updated_manifest, _warnings} <- update_manifest(src_folder, template),
         {:ok, all_environment_manifests} <-
           Electric.Migrations.Sync.get_all_migrations_from_server(app_id) do
      {listing, mismatched} = format_listing(updated_manifest, all_environment_manifests)
      {:ok, listing, mismatched}
    end
  end

  def revert_migration(environment, migration_name, options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, app_id} <- check_app_id(src_folder),
         {:ok, updated_manifest, _warnings} = update_manifest(src_folder, template),
         {:ok, all_environment_manifests} <-
           Electric.Migrations.Sync.get_all_migrations_from_server(app_id) do
      {_listing, mismatched} = format_listing(updated_manifest, all_environment_manifests)

      if Enum.member?(mismatched, {migration_name, environment}) do
        do_revert(src_folder, app_id, environment, migration_name, updated_manifest)
      else
        {:error,
         "The migration #{migration_name} in environment #{environment} is not different. Nothing to revert."}
      end
    end
  end

  defp do_revert(src_folder, app_id, environment, migration_name, current_manifest) do
    with {:ok, %{"migration" => server_migration}} <-
           Electric.Migrations.Sync.get_full_migration_from_server(
             app_id,
             environment,
             migration_name
           ) do
      manifest_revisions = %{
        "satellite_body" => server_migration["satellite_body"],
        "sha256" => server_migration["sha256"]
      }

      updated_migrations =
        for current_migration <- current_manifest["migrations"] do
          case current_migration["name"] do
            ^migration_name ->
              Map.merge(current_migration, manifest_revisions)

            _ ->
              current_migration
          end
        end

      reverted_manifest = Map.put(current_manifest, "migrations", updated_migrations)
      write_manifest(src_folder, reverted_manifest)
      write_migration_body(src_folder, migration_name, server_migration["original_body"])
      {:ok, nil}
    end
  end

  defp format_listing(local_manifest, all_environment_manifests) do
    manifest_lookup =
      for {environment_name, manifest} <- all_environment_manifests do
        lookup =
          for migration <- manifest["migrations"], into: %{} do
            {migration["name"], migration}
          end

        %{"name" => environment_name, "lookup" => lookup}
      end

    {lines, mismatched} =
      Enum.reduce(local_manifest["migrations"], {"", []}, fn migration, {lines, mismatched} ->
        {line, mismatches} =
          Enum.reduce(manifest_lookup, {"#{migration["name"]}", []}, fn environment,
                                                                        {line, mismatches} ->
            sha256 = migration["sha256"]

            {status, mismatch} =
              case environment["lookup"][migration["name"]] do
                nil ->
                  {"-", []}

                %{"sha256" => ^sha256, "status" => status} ->
                  {IO.ANSI.green() <> status <> IO.ANSI.reset(), []}

                _ ->
                  {IO.ANSI.red() <> "different" <> IO.ANSI.reset(),
                   [{migration["name"], environment["name"]}]}
              end

            {line <> "\t#{environment["name"]}: #{status}", mismatches ++ mismatch}
          end)

        {lines <> line <> "\n", mismatched ++ mismatches}
      end)

    {IO.ANSI.reset() <> "\n------ Electric SQL Migrations ------\n\n" <> lines, mismatched}
  end

  defp optionally_write(_func, _folder, _manifest, flag) when flag !== true do
    :ok
  end

  defp optionally_write(func, folder, manifest, _flag) do
    func.(folder, manifest)
  end

  def write_postgres(src_folder, manifest) do
    for migration <- manifest["migrations"] do
      file_path = Path.join([src_folder, migration["name"], @postgres_file_name])
      verbose("Writing PostgreSQL migration '#{file_path}'")
      File.write!(file_path, migration["postgres_body"])
    end

    :ok
  end

  def write_satellite(src_folder, manifest) do
    #    IO.inspect(manifest)
    for migration <- manifest["migrations"] do
      file_path = Path.join([src_folder, migration["name"], @satellite_file_name])
      verbose("Writing Satellite migration '#{file_path}'")
      File.write!(file_path, migration["satellite_raw"])
    end

    :ok
  end

  defp update_manifest(src_folder, template, add_raw_satellite \\ false) do
    with {:ok, updated_manifest, warnings} <-
           src_folder
           |> read_manifest()
           |> add_triggers_to_manifest(src_folder, template, add_raw_satellite) do
      write_manifest(src_folder, updated_manifest)
      #      IO.puts("***************************")
      #      IO.inspect(updated_manifest)
      {:ok, updated_manifest, warnings}
    else
      {:error, errors} ->
        {:error, errors}

      {:error, _updated_manifest, errors} ->
        {:error, errors}
    end
  end

  defp update_manifest_app_id(src_folder, app_id) do
    manifest = read_manifest(src_folder)
    updated_manifest = Map.merge(manifest, %{"app_id" => app_id})
    write_manifest(src_folder, updated_manifest)
    {:ok, nil}
  end

  defp check_app_id(src_folder) do
    manifest = read_manifest(src_folder)

    case manifest["app_id"] do
      nil ->
        {:error, "Please set the app name"}

      app_id ->
        verbose(["Using app id ", :yellow, "#{app_id}"])
        {:ok, app_id}
    end
  end

  defp check_migrations_folder(options) do
    migrations_folder = Map.get(options, :migrations_dir, "migrations") |> Path.expand()

    verbose("Checking for migrations directory '#{migrations_folder}'")

    if not File.exists?(migrations_folder) do
      {:error, ["Couldn't find the migrations folder at #{migrations_folder}"]}
    else
      verbose("Migrations directory '#{migrations_folder}' exists")

      if Path.basename(migrations_folder) == "migrations" do
        {:ok, migrations_folder}
      else
        {:error, ["The migrations folder must be called \"migrations\""]}
      end
    end
  end

  def slugify_title(migration_title, datetime) do
    slug =
      String.downcase(migration_title)
      |> String.replace(~r/[^a-z|\d]/, "_")
      |> String.replace(~r/_{2,}/, "_")
      |> String.replace_leading("_", "")
      |> String.replace_trailing("_", "")

    ts =
      DateTime.truncate(datetime, :millisecond)
      |> DateTime.to_iso8601(:basic)
      |> String.replace("T", "_")
      |> String.replace("Z", "")
      |> String.replace(".", "_")

    "#{ts}_#{slug}" |> String.slice(0..64)
  end

  defp add_migration(migrations_folder, migration_title, app_id \\ nil) do
    datetime = DateTime.utc_now()
    migration_name = slugify_title(migration_title, datetime)
    migration_folder = Path.join(migrations_folder, migration_name)
    File.mkdir_p!(migration_folder)

    {body, _bindings} =
      Code.eval_quoted(@migration_template,
        title: migration_title,
        name: migration_name
      )

    migration_file_path = Path.join([migration_folder, @migration_file_name])
    verbose("Writing migration file '#{migration_file_path}'")
    File.write!(migration_file_path, body)
    add_migration_to_manifest(migrations_folder, migration_name, migration_title, body, app_id)

    {:ok, nil}
  end

  def get_template() do
    @satellite_template
  end

  defp add_migration_to_manifest(src_folder, name, title, body, app_id) do
    current = read_manifest(src_folder)

    migrations_list =
      current["migrations"] ++
        [
          %{
            "name" => name,
            "title" => title,
            "sha256" => strip_comments(body) |> calc_hash(),
            "encoding" => "escaped",
            "satellite_body" => []
          }
        ]

    updated = Map.merge(current, %{"migrations" => migrations_list})

    updated =
      if app_id != nil do
        Map.merge(updated, %{"app_id" => app_id})
      else
        updated
      end

    write_manifest(src_folder, updated)
  end

  defp read_manifest(src_folder) do
    manifest_path = Path.join(src_folder, @manifest_file_name)

    if File.exists?(manifest_path) do
      File.read!(manifest_path)
      |> Jason.decode!()
    else
      %{"migrations" => []}
    end
  end

  defp write_manifest(src_folder, manifest) do
    manifest_path = Path.join(src_folder, @manifest_file_name)

    if File.exists?(manifest_path) do
      File.rm(manifest_path)
    end

    verbose("Writing manifest '#{manifest_path}'")
    File.write!(manifest_path, manifest_json(manifest))
  end

  defp write_migration_body(src_folder, migration_name, original_body) do
    migration_path = Path.join([src_folder, migration_name, @migration_file_name])

    if File.exists?(migration_path) do
      File.rm(migration_path)
    end

    verbose("Writing migration '#{migration_path}'")

    File.write!(migration_path, original_body)
  end

  def manifest_json(manifest) do
    manifest
    |> remove_original_bodies()
    |> remove_satellite_raw()
    |> Jason.encode!(pretty: true)
  end

  defp add_postgres_bodies(manifest, flag) when flag !== true do
    {:ok, manifest, nil}
  end

  defp add_postgres_bodies(manifest, _flag) do
    migrations = manifest["migrations"]

    {status, migrations, messages} =
      1..length(migrations)
      |> Enum.map(&Enum.take(migrations, &1))
      |> Enum.reduce_while({:ok, [], []}, fn subset,
                                             {_status, migrations_with_postgres, messages} ->
        case add_postgres_to_migrations(subset) do
          {:ok, migration, nil} ->
            {:cont, {:ok, migrations_with_postgres ++ [migration], messages}}

          {:ok, migration, warnings} ->
            {:cont, {:ok, migrations_with_postgres ++ [migration], messages ++ warnings}}

          {:error, errors} ->
            {:halt, {:error, [], errors}}
        end
      end)

    {status, Map.merge(manifest, %{"migrations" => migrations}), messages}
  end

  def add_postgres_to_migrations(migrations) do
    migration = List.last(migrations)

    verbose("Generating PostgreSQL migration #{migration["name"]}")

    case Electric.Databases.Postgres.Generation.postgres_for_migrations_w_strings(migrations) do
      {:ok, postgres_body, warnings} ->
        {:ok, Map.merge(migration, %{"postgres_body" => postgres_body}), warnings}

      {:error, reasons} ->
        {:error, reasons}
    end
  end

  defp write_js_bundle(src_folder, manifest, app_id, environment) do
    updated = Map.merge(manifest, %{"app_id" => app_id, "environment" => environment})

    {result, _bindings} = Code.eval_quoted(@bundle_template, migrations: manifest_json(updated))

    dist_folder = Path.join([src_folder, @dist_folder_name])
    File.mkdir_p!(dist_folder)
    bundle_path = Path.join([dist_folder, @js_bundle_file_name])

    if File.exists?(bundle_path) do
      File.rm(bundle_path)
    end

    File.write!(bundle_path, result)
  end

  defp calc_hash(with_triggers) do
    sha = :crypto.hash(:sha256, with_triggers)
    base16 = Base.encode16(sha)
    String.downcase(base16)
  end

  defp add_original_bodies(manifest, src_folder) do
    migrations =
      for migration <- manifest["migrations"] do
        original_body =
          Path.join([src_folder, migration["name"], @migration_file_name])
          |> File.read!()

        Map.put(migration, "original_body", original_body)
      end

    Map.merge(manifest, %{"migrations" => migrations})
  end

  defp remove_original_bodies(manifest) do
    migrations =
      for migration <- manifest["migrations"] do
        Map.delete(migration, "original_body")
      end

    Map.merge(manifest, %{"migrations" => migrations})
  end

  defp remove_satellite_raw(manifest) do
    migrations =
      for migration <- manifest["migrations"] do
        Map.delete(migration, "satellite_raw")
      end

    Map.merge(manifest, %{"migrations" => migrations})
  end

  defp add_triggers_to_manifest(manifest, src_folder, template, add_raw_satellite) do
    manifest_with_original = add_original_bodies(manifest, src_folder)
    migrations_with_original = manifest_with_original["migrations"]

    {status, migrations, messages} =
      1..length(migrations_with_original)
      |> Enum.map(&Enum.take(migrations_with_original, &1))
      |> Enum.reduce_while({:ok, [], []}, fn subset,
                                             {_status, migrations_with_triggers, messages} ->
        case add_triggers_to_migration(subset, template, add_raw_satellite) do
          {:ok, migration, nil} ->
            {:cont, {:ok, migrations_with_triggers ++ [migration], messages}}

          {:ok, migration, warnings} ->
            {:cont, {:ok, migrations_with_triggers ++ [migration], messages ++ warnings}}

          {:error, errors} ->
            {:halt, {:error, [], errors}}
        end
      end)

    {status, Map.merge(manifest, %{"migrations" => migrations}), messages}
  end

  def strip_comments(sql) do
    Electric.Migrations.Lexer.clean_up_sql(sql)
  end

  @doc false
  def add_triggers_to_migration(migration_set, template, add_raw_satellite \\ false) do
    migration = List.last(migration_set)
    hash = strip_comments(migration["original_body"]) |> calc_hash()

    if hash == migration["sha256"] && add_raw_satellite === false do
      {:ok, migration, []}
    else
      case Electric.Migrations.Triggers.add_triggers_to_last_migration(migration_set, template) do
        {:error, reasons} ->
          {:error, reasons}

        {satellite_sql, warnings} ->
          satellite_body = Electric.Migrations.Lexer.get_statements(satellite_sql)

          if add_raw_satellite do
            {:ok,
             Map.merge(migration, %{
               "satellite_body" => satellite_body,
               "satellite_raw" => satellite_sql,
               "sha256" => hash
             }), warnings}
          else
            {:ok, Map.merge(migration, %{"satellite_body" => satellite_body, "sha256" => hash}),
             warnings}
          end
      end
    end
  end
end
