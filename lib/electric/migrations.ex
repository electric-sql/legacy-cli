defmodule Electric.Migrations do
  @moduledoc """
  The `Migrations` context.
  Munges sql migrations and uploads them to the server
  """

  @migration_file_name "migration.sql"
  @satellite_file_name "satellite.sql"
#  @postgre_file_name "postgre.sql"
  @publish_lock_file_name ".published"
  @manifest_file_name "manifest.json"
  @bundle_file_name "manifest.bundle.json"
  @js_bundle_file_name "manifest.bundle.js"
  @trigger_template EEx.compile_file("lib/electric/triggers.eex")
  @bundle_template EEx.compile_file("lib/electric/bundle_js.eex")

  @doc """
Takes a folder which contains sql migration files and adds the SQLite triggers for any newly created tables
"""
  def build_migrations(_src_folder) do

  end

  def send_migrations_to_api(_sql_file_paths) do
    throw :NotImplemented
  end

  def get_template() do
    @trigger_template
  end

  @doc """
  Takes a folder which contains sql migration files and adds the SQLite triggers for any newly created tables.
  """
  def add_triggers(src_folder, template) do
    ordered_migration_paths(src_folder) |> add_triggers_to_migrations(template)
  end

  @doc """
  Writes a json manifest file in the migrations root folder listing all the migration names
  """
  def write_manifest(src_folder) do
    manifest_path = Path.join(src_folder, @manifest_file_name)
    migration_names = for migration_folder <- ordered_migration_paths(src_folder) do
      Path.basename(migration_folder)
    end
    manifest = Jason.encode!(%{"migrations" => migration_names}) |> Jason.Formatter.pretty_print()
    if File.exists?(manifest_path) do
      File.rm(manifest_path)
    end
    File.write(manifest_path, manifest)
  end

  @doc """
  Writes a json bundle file in the migrations root folder listing all the migrations and giving their content
  """
  def write_bundle(src_folder) do
    migrations = create_bundle(src_folder)
    bundle_path = Path.join(src_folder, @bundle_file_name)
    if File.exists?(bundle_path) do
      File.rm(bundle_path)
    end
    File.write(bundle_path, migrations)
  end

  @doc """
  Writes a js bundle file in the migrations root folder listing all the migrations and giving their content.
  Exports the migrations bundle as a js object called "migrations"
  """
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
    migration_names = for file_path <- sql_file_paths do
      Path.dirname(file_path) |> Path.basename()
    end

    for migration_name <- Enum.sort(migration_names) do
      Path.join(src_folder, migration_name)
    end
  end

  defp create_bundle(src_folder) do
    migrations = for migration_folder <- ordered_migration_paths(src_folder) do
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
          regex = ~r/ElectricDB Migration[\s]*(.*?)[\s]*\*/
          matches = Regex.run(regex, body)
          case Jason.decode(List.last(matches)) do
            {:ok, metadata} -> metadata
            {:error, reason} -> {:error, reason}
          end
        {:error, reason} -> {:error, reason}
    end
  end

  defp file_header(hash, name) do
    """
    /*
    ElectricDB Migration
    {"metadata": {"name": "#{name}", "sha256": "#{hash}"}}
    */
    """
  end

  defp add_triggers_to_migrations(ordered_migration_paths, template) do
    ## throwing tuples funky!
    try do
      ordered_migrations = for migration_folder_path <- ordered_migration_paths do
        migration_file_path = Path.join([migration_folder_path, @migration_file_name])
        case File.read(migration_file_path) do
          {:ok, sql} ->
            case validate_sql(sql) do
              :ok -> sql
              {:error, reason} -> throw({:error, reason})
            end
          {:error, reason} -> throw({:error, reason})
        end
      end
      # needs to fail early so has to start at the first migration and go through
      for {migration_folder_path, i} <- Enum.with_index(ordered_migration_paths) do
        subset_of_migrations = Enum.take(ordered_migrations, i + 1)
        # this is using a migration file path and all the migrations up to, an including this migration
        case add_triggers_to_migration_folder(migration_folder_path, subset_of_migrations, template) do
          :ok -> :ok
          {:error, reason} -> throw({:error, reason})
        end
      end
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def add_triggers_to_migration_folder(migration_folder_path, ordered_migrations, template) do
    migration_name = Path.basename(migration_folder_path)
#    migration_file_path = Path.join(migration_folder_path, @migration_file_name)
    satellite_file_path = Path.join(migration_folder_path, @satellite_file_name)
#    postgres_file_path = Path.join(migration_folder_path, @postgre_file_name)
    publish_lock_file_path = Path.join(migration_folder_path, @publish_lock_file_name)

    with_triggers = add_triggers_to_last_migration(ordered_migrations, template)
    hash = calc_hash(with_triggers)

    # firstly check to see if this source migration file has already been published
    if File.exists?(publish_lock_file_path) do
      metadata = get_metadata(satellite_file_path)
      if metadata["sha256"] == hash do
        # if matches then its a happy no-op
        :ok
      else
        # If a published file has been modified this is an error state and so fail. TODO Need to think what remedy is for dev
        {:error, "Migration #{migration_name} has already been published and cannot be changed"}
      end
    else
      # otherwise check for the unpublished, but already decorated one
      if File.exists?(satellite_file_path) do
        metadata = get_metadata(satellite_file_path)
        if metadata["sha256"] == hash do
          # if matches then its a happy no-op
          :ok
        else
          # if it exists but doesnt match fail and offer the dev to force it. TODO Need to think what remedy is for dev
          {:error, "Migration #{migration_name} already exists locally if you would like to overwrite it ..."}
        end
      else
        # if neither file already exists go ahead and write it
        header = file_header(hash, migration_name)
        File.write(satellite_file_path, header <> with_triggers)
      end
    end
  end

  @doc false
  def add_triggers_to_last_migration(ordered_migrations, template) do
    # adds triggers for all tables to the end of the last migration
    table_infos = all_tables_info(ordered_migrations)
    sql_in = List.last(ordered_migrations)
    template_all_the_things(sql_in, table_infos, template)
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
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT name, sql FROM sqlite_master WHERE type='table' AND name!='_oplog';")
    info = get_rows_while(conn, statement, [])
    :ok = Exqlite.Sqlite3.release(conn, statement)

    # for each table
    infos = for [table_name, _sql] <- info do
      # column names
      {:ok, info_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{table_name});")
      columns = Enum.reverse(get_rows_while(conn, info_statement, []))
      column_names = for [_cid, name, _type, _notnull, _dflt_value, _pk] <- columns do
        name
      end
      # private keys columns
      private_key_column_names = for [_cid, name, _type, _notnull, _dflt_value, pk] when pk == 1 <- columns do
        name
      end

      # foreign keys
      {:ok, foreign_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA foreign_key_list(#{table_name});")
      foreign_keys = get_rows_while(conn, foreign_statement, [])

      foreign_keys = for [_a, _b, parent_table, child_key, parent_key, _c, _d, _e] <- foreign_keys do
        %{:child_key => child_key, :parent_key => parent_key, :table => "#{namespace}.#{parent_table}"}
      end

      %{:table_name => table_name,
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
      :done -> rows
    end
  end

  @doc false
  def template_all_the_things(original_sql, tables, template) do
    patched_sql = Enum.reduce(tables, original_sql, fn {table_full_name, table}, acc -> String.replace(acc, " #{table.table_name} ", " #{table_full_name} ") end)
    {result, _bindings} = Code.eval_quoted(template,
      is_init: true,
      original_sql: patched_sql,
      tables: tables)
    result
  end

end
