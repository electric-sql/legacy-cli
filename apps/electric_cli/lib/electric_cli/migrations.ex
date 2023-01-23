defmodule ElectricCli.Migrations do
  @moduledoc """
  The `Migrations` context.
  Munges sql migrations and uploads them to the server
  """
  import ElectricCli.Util, only: [verbose: 1]

  alias ElectricCli.Config
  alias ElectricCli.Config.Environment
  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration
  alias ElectricCli.Migrations.Api
  alias ElectricCli.Util

  @migration_filename "migration.sql"
  @postgres_filename "postgres.sql"
  @satellite_filename "satellite.sql"

  @migration_template_path "#{__DIR__}/templates/#{@migration_filename}.eex"
  @satellite_template_path "#{__DIR__}/templates/#{@satellite_filename}.eex"

  @migration_template EEx.compile_file(@migration_template_path)
  @satellite_template EEx.compile_file(@satellite_template_path)

  for template <- [@migration_template_path, @satellite_template_path] do
    @external_resource template
  end

  @type body_style() :: :none | :text | :list

  def satellite_template do
    @satellite_template
  end

  @doc """
  Creates the migrations folder and adds an initial migration to it.
  """
  def init_migrations(
        %Config{app: app, directories: %{migrations: migrations_dir}},
        should_verify_app \\ true
      ) do
    verbose("Using migrations directory `#{migrations_dir}`")

    exists = File.exists?(migrations_dir)

    with :ok <- init_manifest(app, migrations_dir, exists),
         {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, should_verify_app),
         false <- has_init_migration(manifest),
         {:ok, _path} <- add_migration(manifest, migrations_dir, "init") do
      :ok
    else
      true ->
        :ok
    end
  end

  @doc """
  Updates the `app` in the migrations manifest.
  """
  def update_app(%Config{app: app, directories: %{migrations: migrations_dir}}) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, false) do
      Manifest.update_app(manifest, app, migrations_dir)
    end
  end

  @doc """
  Adds a new migration to the existing set of migrations.
  """
  def new_migration(%Config{app: app, directories: %{migrations: migrations_dir}}, migration_name) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, false) do
      add_migration(manifest, migrations_dir, migration_name)
    end
  end

  @doc """
  List migrations and their status for a given app and env.
  """
  def list_migrations(%Config{app: app, directories: %{migrations: migrations_dir}}, %Environment{
        slug: env
      }) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, true),
         {:ok, %Manifest{} = manifest, []} <- hydrate_manifest(manifest, migrations_dir),
         {:ok, %Manifest{} = server_manifest} <- Api.get_server_migrations(app, env) do
      format_migration_listing(manifest, server_manifest)
    end
  end

  def revert_migration(
        %Config{app: app, directories: %{migrations: migrations_dir}},
        %Environment{slug: env},
        migration_name
      ) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, true),
         {:ok, %Manifest{} = local_manifest, []} <- hydrate_manifest(manifest, migrations_dir),
         {:local, %Migration{} = local_migration} <-
           {:local, Manifest.named_migration(local_manifest, migration_name)},
         {:ok, %Manifest{} = server_manifest} <- Api.get_server_migrations(app, env),
         {:server, %Migration{} = server_migration} <-
           {:server, Manifest.named_migration(server_manifest, migration_name)},
         {:ok, _, mismatched} <- format_migration_listing(local_manifest, server_manifest),
         _ <- IO.inspect({:mismatched, mismatched}),
         _ <- IO.inspect({:local_migration, local_migration}),
         true <- mismatched_has_target_migration(mismatched, local_migration),
         :ok <- revert_and_save_manifest(local_manifest, server_migration, migrations_dir) do
      overwrite_migration_sql(server_migration, migrations_dir)
    else
      false ->
        {:error, "Nothing to revert.",
         [
           "The local migration `#{migration_name}` matches the migration " <>
             "with the same name applied to environment `#{env}`."
         ]}

      {:local, nil} ->
        {:error, "Migration `#{migration_name}` not found locally."}

      {:server, nil} ->
        {:error, "Migration `#{migration_name}` not found at environment `#{env}`."}

      alt ->
        IO.inspect({:alt, alt})

        alt
    end
  end

  defp revert_and_save_manifest(
         %Manifest{migrations: migrations} = local_manifest,
         %Migration{} = server_migration,
         migrations_dir
       ) do
    migrations =
      migrations
      |> Enum.map(&revert_matching_migration(&1, server_migration))

    local_manifest
    |> Map.put(:migrations, migrations)
    |> Manifest.save(migrations_dir)
  end

  defp revert_matching_migration(
         %Migration{name: name} = migration,
         %Migration{name: target_name, satellite_body: satellite_body, sha256: sha256}
       )
       when name == target_name do
    migration
    |> Map.put(:satellite_body, satellite_body)
    |> Map.put(:sha256, sha256)
  end

  defp revert_matching_migration(%Migration{} = migration, _) do
    migration
  end

  defp overwrite_migration_sql(
         %Migration{name: name, original_body: original_body},
         migrations_dir
       ) do
    [migrations_dir, name, @migration_filename]
    |> Path.join()
    |> File.write(original_body)
  end

  defp init_manifest(_app, _migrations_dir, true) do
    :ok
  end

  defp init_manifest(app, migrations_dir, false) do
    verbose("Creating `#{migrations_dir}`")

    with :ok <- File.mkdir_p(migrations_dir) do
      Manifest.init(app, migrations_dir)
    end
  end

  defp has_init_migration(%Manifest{migrations: migrations}) do
    migrations
    |> Enum.any?(fn %Migration{title: title} -> title == "init" end)
  end

  defp format_migration_listing(
         %Manifest{migrations: local_migrations},
         %Manifest{migrations: server_migrations}
       ) do
    server_migration_map =
      server_migrations
      |> Enum.map(fn %Migration{name: name} = migration -> {name, migration} end)
      |> Enum.into(%{})

    {rows, mismatched} =
      local_migrations
      |> Enum.reduce({[], []}, fn %Migration{name: name, sha256: sha256, title: title} = migration,
                                  {rows, mismatched} ->
        {status, is_mismatch} =
          case Map.get(server_migration_map, name) do
            nil ->
              {"-", false}

            %{"sha256" => ^sha256, "status" => status} ->
              {IO.ANSI.green() <> status <> IO.ANSI.reset(), false}

            _ ->
              {IO.ANSI.red() <> "different" <> IO.ANSI.reset(), true}
          end

        row = [name, title, status]
        rows = rows ++ [row]

        mismatched =
          case is_mismatch do
            true ->
              mismatched ++ [migration]

            false ->
              mismatched
          end

        {rows, mismatched}
      end)

    {:ok, {:results, rows, ["Name", "Title", "Status"]}, mismatched}
  end

  defp mismatched_has_target_migration([], %Migration{}), do: false

  defp mismatched_has_target_migration(mismatched_migrations, %Migration{name: target_name}) do
    mismatched_migrations
    |> Enum.any?(fn %Migration{name: name} -> name == target_name end)
  end

  def optionally_write_postgres(_, _, false), do: :ok

  def optionally_write_postgres(%Manifest{} = manifest, migrations_dir, true) do
    manifest
    |> write_postgres(migrations_dir)
  end

  def optionally_write_satellite(_, _, false), do: :ok

  def optionally_write_satellite(%Manifest{} = manifest, migrations_dir, true) do
    write_satellite(manifest, migrations_dir)
  end

  defp write_postgres(%Manifest{migrations: migrations}, migrations_dir) do
    migrations
    |> Enum.reduce(:ok, &write_postgres(&1, &2, migrations_dir))
  end

  defp write_postgres(%Migration{name: name, postgres_body: postgres_body}, :ok, migrations_dir) do
    [migrations_dir, name, @postgres_filename]
    |> Path.join()
    |> File.write(postgres_body)
  end

  defp write_postgres(_, error, _) do
    error
  end

  defp write_satellite(%Manifest{migrations: migrations}, migrations_dir) do
    migrations
    |> Enum.reduce(:ok, &write_satellite(&1, &2, migrations_dir))
  end

  defp write_satellite(%Migration{name: name, satellite_raw: satellite_raw}, :ok, migrations_dir) do
    [migrations_dir, name, @satellite_filename]
    |> Path.join()
    |> File.write(satellite_raw)
  end

  defp write_satellite(_, error, _) do
    error
  end

  def hydrate_manifest(
        %Manifest{} = manifest,
        migrations_dir,
        postgres_flag \\ false,
        satellite_flag \\ false
      ) do
    with {:ok, manifest} <- add_original_bodies(manifest, migrations_dir),
         {:ok, manifest, postgres_warnings} <- add_postgres_bodies(manifest, postgres_flag),
         {:ok, manifest, satellite_warnings} <- add_satellite_triggers(manifest, satellite_flag) do
      {:ok, manifest, satellite_warnings ++ postgres_warnings}
    else
      {:error, _updated_manifest, errors} ->
        {:error, errors}

      {:error, errors} ->
        {:error, errors}
    end
  end

  defp add_original_bodies(%Manifest{migrations: migrations} = manifest, migrations_dir) do
    migrations =
      migrations
      |> Enum.map(&add_original_body(&1, migrations_dir))

    {:ok, %{manifest | migrations: migrations}}
  end

  defp add_original_body(%Migration{name: name} = migration, migrations_dir) do
    original_body =
      [migrations_dir, name, @migration_filename]
      |> Path.join()
      |> File.read!()

    migration
    |> Map.put(:original_body, original_body)
  end

  # XXX @thruflo -- I stopped following the untyped rabbit hole
  # at this point. So this function converts the manifest to a
  # string keyed map and hands the damn thing over.
  defp add_satellite_triggers(%Manifest{} = manifest, satellite) do
    manifest_data = Util.string_keyed_nested_map_from_nested_struct(manifest)

    with {:ok, manifest_data, warnings} <-
           add_triggers_to_manifest(manifest_data, @satellite_template, satellite) do
      {:ok, Manifest.new(manifest_data), warnings}
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

  defp add_migration(%Manifest{} = manifest, dir, title) when is_binary(title) do
    name = slugify_title(title, DateTime.utc_now())

    migration_folder = Path.join(dir, name)
    migration_filepath = Path.join(migration_folder, @migration_filename)
    relative_filepath = Path.relative_to_cwd(migration_filepath)

    verbose("Writing migration file `#{relative_filepath}`")

    {body, _bindings} = Code.eval_quoted(@migration_template, title: title, name: name)

    migration = %Migration{
      name: name,
      title: title,
      sha256: calc_hash(body),
      encoding: "escaped",
      satellite_body: []
    }

    with :ok <- File.mkdir_p(migration_folder),
         :ok <- File.write(migration_filepath, body),
         :ok <- Manifest.append_migration(manifest, migration, dir) do
      {:ok, relative_filepath}
    end
  end

  # XXX switch from typed to string keyed map.
  defp add_postgres_bodies(%Manifest{} = manifest, false) do
    {:ok, manifest, []}
  end

  defp add_postgres_bodies(%Manifest{} = manifest, true) do
    manifest_data = Util.string_keyed_nested_map_from_nested_struct(manifest)

    with {:ok, manifest_data, warnings} <- add_postgres_bodies(manifest_data) do
      {:ok, Manifest.new(manifest_data), warnings}
    end
  end

  defp add_postgres_bodies(manifest) do
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

  defp add_postgres_to_migrations(migrations) do
    migration = List.last(migrations)

    verbose("Generating PostgreSQL migration `#{migration["name"]}`")

    migrations
    |> normalize_migration_keys()
    |> ElectricMigrations.Postgres.postgres_sql_for_last_migration()
    |> case do
      {:ok, postgres_body, warnings} ->
        {:ok, Map.merge(migration, %{"postgres_body" => postgres_body}), warnings}

      {:error, reasons} ->
        {:error, reasons}
    end
  end

  defp calc_hash(sql) do
    stripped_sql = ElectricMigrations.Sqlite.strip_comments(sql)
    sha = :crypto.hash(:sha256, stripped_sql)
    base16 = Base.encode16(sha)
    String.downcase(base16)
  end

  defp add_triggers_to_manifest(manifest, template, add_raw_satellite) do
    migrations_with_original = manifest["migrations"]

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

  defp add_triggers_to_migration(migration_set, template, add_raw_satellite) do
    migration = List.last(migration_set)
    hash = calc_hash(migration["original_body"])

    if hash == migration["sha256"] && add_raw_satellite === false do
      {:ok, migration, []}
    else
      normalized_migrations = normalize_migration_keys(migration_set)

      case ElectricMigrations.Sqlite.add_triggers_to_last_migration(
             normalized_migrations,
             template
           ) do
        {:error, reasons} ->
          {:error, reasons}

        {satellite_sql, warnings} ->
          satellite_body = ElectricMigrations.Sqlite.get_statements(satellite_sql)

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

  defp normalize_migration_keys(migrations) do
    for migration <- migrations do
      %{name: migration["name"], original_body: migration["original_body"]}
    end
  end
end
