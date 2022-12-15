defmodule Electric.Command.MigrationsTest do
  use ExUnit.Case

  alias Electric.Config

  setup_all do
    tmp_dir = "tmp"
    File.rm_rf(tmp_dir)
    File.mkdir(tmp_dir)
  end

  def temp_folder() do
    Path.join(["tmp", UUID.uuid4()])
  end

  describe "run commands" do
    setup do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])

      config =
        Config.new(
          root: temp,
          migrations_dir: migrations_path,
          app_id: "app-name",
          env: "default"
        )

      # create migrations dir
      {:ok, _path} = Config.init(config)

      {:ok, config: config}
    end

    test "build migrations", %{config: config} do
      sql_file_paths = Path.join([config.migrations_dir, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:success, _msg} =
        Electric.Commands.Migrations.build(%{
          args: [],
          flags: [],
          options: %{root: config.root},
          unknown: nil
        })

      assert File.exists?(Path.join([config.migrations_dir, "manifest.json"]))
    end

    test "sync migrations", %{config: config} do
      sql_file_paths = Path.join([config.migrations_dir, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      _migration_folder = Path.dirname(my_new_migration)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:success, msg} =
        Electric.Commands.Migrations.sync(%{
          args: %{},
          flags: [],
          options: %{root: config.root, env: "production"},
          unknown: nil
        })

      assert msg == "Migrations synchronized with server successfully"
    end

    test "new migrations", %{config: config} do
      sql_file_paths = Path.join([config.migrations_dir, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:success, msg} =
        Electric.Commands.Migrations.new(%{
          args: %{migration_title: "Another migration"},
          flags: [],
          options: %{root: config.root},
          unknown: nil
        })

      assert msg == "New migration created"
    end

    test "list migrations", %{config: config} do
      sql_file_paths = Path.join([config.migrations_dir, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      migration_name = Path.dirname(my_new_migration) |> Path.basename()

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:success, msg} =
        Electric.Commands.Migrations.list(%{
          args: %{},
          flags: [],
          options: %{root: config.root},
          unknown: nil
        })

      assert msg ==
               "\e[0m\n------ Electric SQL Migrations ------\n\n#{migration_name}\tdefault: -\n"
    end

    test "revert migrations", %{config: config} do
      sql_file_paths = Path.join([config.migrations_dir, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      migration_name = Path.dirname(my_new_migration) |> Path.basename()

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:error, msg} =
        Electric.Commands.Migrations.revert(%{
          args: %{migration_name: migration_name},
          flags: [],
          options: %{root: config.root, env: "default"},
          unknown: nil
        })

      assert msg ==
               "There was 1 errors:\nThe migration #{migration_name} in environment default is not different. Nothing to revert."
    end
  end
end
