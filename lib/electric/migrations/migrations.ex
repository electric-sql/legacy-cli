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

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, updated_manifest, warnings} = update_manifest(src_folder, template) do
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
  def sync_migrations(app_name, environment, options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, updated_manifest, warnings} = update_manifest(src_folder, template),
         {:ok, _msg} <-
           Electric.Migrations.Sync.sync_migrations(app_name, environment, updated_manifest),
         {:ok, server_manifest} <-
           Electric.Migrations.Sync.get_migrations_from_server(app_name, environment, true),
         :ok <- write_js_bundle(src_folder, server_manifest, environment) do
      if length(warnings) > 0 do
        {:ok, warnings}
      else
        {:ok, nil}
      end
    end
  end

  def list_migrations(app_name, options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, updated_manifest, warnings} = update_manifest(src_folder, template),
         {:ok, all_environment_manifests} <-
           Electric.Migrations.Sync.get_all_migrations_from_server(app_name) do
      {listing, mismatched} = format_listing(updated_manifest, all_environment_manifests)
      {:ok, listing}
    end
  end

  def revert_migration(app_name, environment, migration_name, options) do
    template = Map.get(options, :template, @satellite_template)

    with {:ok, src_folder} <- check_migrations_folder(options),
         {:ok, updated_manifest, warnings} = update_manifest(src_folder, template),
         {:ok, all_environment_manifests} <-
           Electric.Migrations.Sync.get_all_migrations_from_server(app_name) do
      {listing, mismatched} = format_listing(updated_manifest, all_environment_manifests)
      {:ok, listing}
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

    lines =
      for migration <- local_manifest["migrations"], into: "" do
        line =
          for environment <- manifest_lookup, into: "#{migration["name"]}\t" do
            sha256 = migration["sha256"]

            status =
              case environment["lookup"][migration["name"]] do
                nil ->
                  "-"

                %{"sha256" => ^sha256} ->
                  IO.ANSI.green() <> "sync" <> IO.ANSI.reset()

                _ ->
                  IO.ANSI.red() <> "different" <> IO.ANSI.reset()
              end

            "#{environment["name"]}: #{status}\t"
          end

        line <> "\n"
      end

    mismatched = []
    {"\n------ Electric SQL Migrations ------\n\n" <> lines, mismatched}
  end

  defp update_manifest(src_folder, template) do
    with {:ok, updated_manifest, warnings} <-
           src_folder
           |> read_manifest()
           |> add_triggers_to_manifest(src_folder, template),
         cleaned_manifest <- remove_original_bodies(updated_manifest, src_folder) do
      :ok <= write_manifest(src_folder, cleaned_manifest)
      :ok <= write_js_bundle(src_folder, cleaned_manifest)
      {:ok, updated_manifest, warnings}
    else
      {:error, errors} ->
        {:error, errors}

      {:error, [], errors} ->
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
      |> String.replace("T", "")
      |> String.replace("Z", "")
      |> String.replace(".", "")

    "#{ts}_#{slug}" |> String.slice(0..64)
  end

  defp add_migration(migrations_folder, migration_title) do
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
    File.write!(migration_file_path, body)
    add_migration_to_manifest(migrations_folder, migration_name, migration_title, body)

    {:ok, nil}
  end

  def get_template() do
    @satellite_template
  end

  defp add_migration_to_manifest(src_folder, name, title, body) do
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

    write_manifest(src_folder, %{"migrations" => migrations_list})
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

    File.write!(manifest_path, Jason.encode!(manifest) |> Jason.Formatter.pretty_print())
  end

  defp write_js_bundle(src_folder, manifest, environment \\ nil) do
    manifest_json = Jason.encode!(manifest) |> Jason.Formatter.pretty_print()
    {result, _bindings} = Code.eval_quoted(@bundle_template, migrations: manifest_json)

    build_name =
      if environment == nil do
        "local"
      else
        environment
      end

    local_path = Path.join([src_folder, "build", build_name])
    bundle_path = Path.join([local_path, @js_bundle_file_name])

    File.mkdir_p!(local_path)

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

    %{"migrations" => migrations}
  end

  defp remove_original_bodies(manifest, src_folder) do
    migrations =
      for migration <- manifest["migrations"] do
        Map.delete(migration, "original_body")
      end

    %{"migrations" => migrations}
  end

  defp add_triggers_to_manifest(manifest, src_folder, template) do
    manifest_with_original = add_original_bodies(manifest, src_folder)
    migrations_with_original = manifest_with_original["migrations"]

    {status, migrations, messages} =
      1..length(migrations_with_original)
      |> Enum.map(&Enum.take(migrations_with_original, &1))
      |> Enum.reduce_while({:ok, [], []}, fn subset,
                                             {_status, migrations_with_triggers, messages} ->
        case add_triggers_to_migration(subset, template) do
          {:ok, migration, nil} ->
            {:cont, {:ok, migrations_with_triggers ++ [migration], messages}}

          {:ok, migration, warnings} ->
            {:cont, {:ok, migrations_with_triggers ++ [migration], messages ++ warnings}}

          {:error, errors} ->
            {:halt, {:error, [], errors}}
        end
      end)

    {status, %{"migrations" => migrations}, messages}
  end

  def strip_comments(sql) do
    Electric.Migrations.Lexer.clean_up_sql(sql)
  end

  @doc false
  def add_triggers_to_migration(migration_set, template) do
    migration = List.last(migration_set)
    hash = strip_comments(migration["original_body"]) |> calc_hash()

    if hash == migration["sha256"] do
      {:ok, migration, []}
    else
      case Electric.Migrations.Triggers.add_triggers_to_last_migration(migration_set, template) do
        {:error, reasons} ->
          {:error, reasons}

        {satellite_sql, warnings} ->
          satellite_body = Electric.Migrations.Lexer.get_statements(satellite_sql)

          {:ok, Map.merge(migration, %{"satellite_body" => satellite_body, "sha256" => hash}),
           warnings}
      end
    end
  end
end
