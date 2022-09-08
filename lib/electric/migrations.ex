defmodule Electric.Migrations do
  @moduledoc """
  The `Migrations` context.
  Munges sql migrations and uploads them to the server
  """

  @migration_file_name "migration.sql"
  @satellite_file_name "satellite.sql"
  @manifest_file_name "manifest.json"
  @bundle_file_name "manifest.bundle.json"
  @js_bundle_file_name "index.js"
  @migration_template EEx.compile_file("lib/electric/templates/migration.eex")
  @satellite_template EEx.compile_file("lib/electric/templates/triggers.eex")
  @bundle_template EEx.compile_file("lib/electric/templates/bundle_js.eex")

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
      {:error, "Migrations folder at #{migrations_folder} already exists."}
    else
      File.mkdir_p!(migrations_folder)

      case add_migration(migrations_folder, "init") do
        {:ok, _} ->
          {:success, "Your migrations folder with an initial migration has been created"}

        {:success, _} ->
          {:success, "Your migrations folder with an initial migration has been created"}

        {:error, msg} ->
          {:error, msg}
      end
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

      {:error, msg} ->
        {:error, msg}
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
    case check_migrations_folder(options) do
      {:ok, migrations_folder} ->
        template = Map.get(options, :template, @satellite_template)
        ordered_migration_paths(migrations_folder) |> add_triggers_to_migrations(template)

        if flags[:manifest] do
          write_manifest(migrations_folder)
        end

        if flags[:bundle] do
          write_js_bundle(migrations_folder)
        end

        {:success, "Migrations built"}

      {:error, msg} ->
        {:error, msg}
    end
  end

  @doc """
  Does nothing yet
  """
  def sync_migrations(_db, _opts \\ []) do
  end

  defp check_migrations_folder(options) do
    migrations_folder = Map.get(options, :migrations, "migrations")

    if !File.exists?(migrations_folder) do
      {:error, "Couldn't find the migrations folder at #{migrations_folder}"}
    else
      if Path.basename(migrations_folder) == "migrations" do
        {:ok, migrations_folder}
      else
        {:error, "The migrations folder must be called \"migrations\""}
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
    {:success, "Migration file created at #{migration_file_path}"}
  end

  def get_template() do
    @satellite_template
  end

  @doc false
  def write_manifest(src_folder) do
    manifest_path = Path.join(src_folder, @manifest_file_name)

    migration_names =
      for migration_folder <- ordered_migration_paths(src_folder) do
        Path.basename(migration_folder)
      end

    manifest = Jason.encode!(%{"migrations" => migration_names}) |> Jason.Formatter.pretty_print()

    if File.exists?(manifest_path) do
      File.rm(manifest_path)
    end

    File.write(manifest_path, manifest)
  end

  @doc false
  def write_bundle(src_folder) do
    migrations = create_bundle(src_folder)
    bundle_path = Path.join(src_folder, @bundle_file_name)

    if File.exists?(bundle_path) do
      File.rm(bundle_path)
    end

    File.write(bundle_path, migrations)
  end

  @doc false
  def write_js_bundle(src_folder) do
    migrations = create_bundle(src_folder)
    {result, _bindings} = Code.eval_quoted(@bundle_template, migrations: migrations)
    bundle_path = Path.join(src_folder, @js_bundle_file_name)

    if File.exists?(bundle_path) do
      File.rm(bundle_path)
    end

    File.write!(bundle_path, result)
  end

  defp ordered_migration_paths(src_folder) do
    sql_file_paths = Path.join([src_folder, "*", @migration_file_name]) |> Path.wildcard()

    migration_names =
      for file_path <- sql_file_paths do
        Path.dirname(file_path) |> Path.basename()
      end

    for migration_name <- Enum.sort(migration_names) do
      Path.join(src_folder, migration_name)
    end
  end

  defp create_bundle(src_folder) do
    migrations =
      for migration_folder <- ordered_migration_paths(src_folder) do
        satellite_sql_path = Path.join(migration_folder, @satellite_file_name)
        migration_text = File.read!(satellite_sql_path)
        migration_name = Path.basename(migration_folder)
        %{"name" => migration_name, "body" => migration_text}
      end

    Jason.encode!(%{"migrations" => migrations}) |> Jason.Formatter.pretty_print()
  end

  defp calc_hash(with_triggers) do
    sha = :crypto.hash(:sha256, with_triggers)
    base16 = Base.encode16(sha)
    String.downcase(base16)
  end

  defp get_metadata(file_path) do
    case File.read(file_path) do
      {:ok, body} ->
        get_body_metadata(body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_body_metadata(body) do
    regex = ~r/ElectricDB Migration[\s]*(.*?)[\s]*\*/
    matches = Regex.run(regex, body)

    if matches == nil do
      {:error, "no header"}
    else
      case Jason.decode(List.last(matches)) do
        {:ok, metadata} -> metadata["metadata"]
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp file_header(hash, name, title) do
    case title do
      nil ->
        """
        /*
        ElectricDB Migration
        {"metadata": {"name": "#{name}", "sha256": "#{hash}"}}
        */
        """

      _ ->
        """
        /*
        ElectricDB Migration
        {"metadata": {"title": "#{title}", "name": "#{name}", "sha256": "#{hash}"}}
        */
        """
    end
  end

  defp add_triggers_to_migrations(ordered_migration_paths, template) do
    ## throwing tuples funky!
    try do
      ordered_migrations =
        for migration_folder_path <- ordered_migration_paths do
          migration_file_path = Path.join([migration_folder_path, @migration_file_name])

          case File.read(migration_file_path) do
            {:ok, sql} ->
              case validate_sql(sql) do
                :ok -> sql
                {:error, reason} -> throw({:error, reason})
              end

            {:error, reason} ->
              throw({:error, reason})
          end
        end

      # needs to fail early so has to start at the first migration and go through
      for {_migration_folder_path, i} <- Enum.with_index(ordered_migration_paths) do
        subset_of_migrations = Enum.take(ordered_migrations, i + 1)
        subset_of_migration_folders = Enum.take(ordered_migration_paths, i + 1)

        # this is using a migration file path and all the migrations up to, an including this migration
        case add_triggers_to_migration_folder(
               subset_of_migration_folders,
               subset_of_migrations,
               template
             ) do
          :ok -> :ok
          {:error, reason} -> throw({:error, reason})
        end
      end
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def add_triggers_to_migration_folder(ordered_folder_paths, ordered_migrations, template) do
    migration_folder_path = List.last(ordered_folder_paths)
    migration_name = Path.basename(migration_folder_path)
    satellite_file_path = Path.join(migration_folder_path, @satellite_file_name)
    with_triggers = add_triggers_to_last_migration(ordered_migrations, template)

    migration_fingerprint =
      if length(ordered_migrations) > 1 do
        previous_satellite_migration_file_path =
          Path.join(Enum.at(ordered_folder_paths, -2), @satellite_file_name)

        previous_metadata = get_metadata(previous_satellite_migration_file_path)
        "#{with_triggers}#{previous_metadata["sha256"]}"
      else
        with_triggers
      end

    hash = calc_hash(migration_fingerprint)

    if File.exists?(satellite_file_path) do
      metadata = get_metadata(satellite_file_path)

      if metadata["sha256"] != hash do
        IO.puts("Warning: The migration #{migration_name} has been modified.")
        File.rm(satellite_file_path)
      end
    end

    if !File.exists?(satellite_file_path) do
      header =
        case get_body_metadata(List.last(ordered_migrations)) do
          {:error, _reason} ->
            file_header(hash, migration_name, nil)

          existing_metadata ->
            file_header(hash, migration_name, existing_metadata["title"])
        end

      File.write!(satellite_file_path, header <> with_triggers)
      :ok
    else
      :ok
    end
  end

  @doc false
  def add_triggers_to_last_migration(ordered_migrations, template) do
    # adds triggers for all tables to the end of the last migration
    table_infos = all_tables_info(ordered_migrations)
    sql_in = List.last(ordered_migrations)
    is_init = length(ordered_migrations) == 1
    template_all_the_things(sql_in, table_infos, template, is_init)
  end

  @doc false
  def validate_sql(sql_in) do
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    case Exqlite.Sqlite3.execute(conn, sql_in) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def created_table_names(sql_in) do
    info = all_tables_info(sql_in)
    Map.keys(info)
  end

  @doc false
  def all_tables_info(all_migrations) do
    namespace = "main"
    # get all the table names
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    for migration <- all_migrations do
      :ok = Exqlite.Sqlite3.execute(conn, migration)
    end

    {:ok, statement} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name!='_oplog';"
      )

    info = get_rows_while(conn, statement, [])
    :ok = Exqlite.Sqlite3.release(conn, statement)

    # for each table
    infos =
      for [table_name, _sql] <- info do
        # column names
        {:ok, info_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{table_name});")
        columns = Enum.reverse(get_rows_while(conn, info_statement, []))

        column_names =
          for [_cid, name, _type, _notnull, _dflt_value, _pk] <- columns do
            name
          end

        # private keys columns
        private_key_column_names =
          for [_cid, name, _type, _notnull, _dflt_value, pk] when pk == 1 <- columns do
            name
          end

        # foreign keys
        {:ok, foreign_statement} =
          Exqlite.Sqlite3.prepare(conn, "PRAGMA foreign_key_list(#{table_name});")

        foreign_keys = get_rows_while(conn, foreign_statement, [])

        foreign_keys =
          for [_a, _b, parent_table, child_key, parent_key, _c, _d, _e] <- foreign_keys do
            %{
              :child_key => child_key,
              :parent_key => parent_key,
              :table => "#{namespace}.#{parent_table}"
            }
          end

        %{
          :table_name => table_name,
          :columns => column_names,
          :namespace => namespace,
          :primary => private_key_column_names,
          :foreign_keys => foreign_keys
        }
      end

    Enum.into(infos, %{}, fn info -> {"#{namespace}.#{info.table_name}", info} end)
  end

  defp get_rows_while(conn, statement, rows) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, row} ->
        get_rows_while(conn, statement, [row | rows])

      :done ->
        rows
    end
  end

  @doc false
  def template_all_the_things(original_sql, tables, template, is_init) do
    ## strip the old header
    patched_sql = String.replace(original_sql, ~r/\A\/\*((?s).*)\*\/\n/, "")
    ## template
    {result, _bindings} =
      Code.eval_quoted(template,
        is_init: is_init,
        original_sql: patched_sql,
        tables: tables
      )

    result
  end
end
