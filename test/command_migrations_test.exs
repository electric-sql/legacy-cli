defmodule CommandMigrationsTest do
  use ExUnit.Case

  setup_all do
    tmp_dir = "tmp"
    File.rm_rf(tmp_dir)
    File.mkdir(tmp_dir)
  end

  def temp_folder() do
    Path.join(["tmp", UUID.uuid4()])
  end

  describe "run commands" do
    test "init migrations" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])

      {:success, msg} =
        Electric.Commands.Migrations.init(%{
          args: nil,
          flags: nil,
          options: %{:dir => temp},
          unknown: nil
        })

      assert File.exists?(migrations_path)
      assert msg == "Migrations initialised"
    end

    test "build migrations" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])

      {:success, msg} =
        Electric.Commands.Migrations.init(%{
          args: [],
          flags: [],
          options: %{:dir => temp},
          unknown: nil
        })

      assert File.exists?(migrations_path)
      assert msg == "Migrations initialised"

      sql_file_paths = Path.join([migrations_path, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      migration_folder = Path.dirname(my_new_migration)

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
          options: %{:dir => migrations_path},
          unknown: nil
        })

      assert File.exists?(Path.join([migration_folder, "satellite.sql"]))
    end

    test "build migrations errors" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])

      {:success, msg} =
        Electric.Commands.Migrations.init(%{
          args: [],
          flags: [],
          options: %{:dir => temp},
          unknown: nil
        })

      assert File.exists?(migrations_path)
      assert msg == "Migrations initialised"

      sql_file_paths = Path.join([migrations_path, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      #      migration_folder = Path.dirname(my_new_migration)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:error, msg} =
        Electric.Commands.Migrations.build(%{
          args: [],
          flags: [],
          options: %{:dir => temp},
          unknown: nil
        })

      assert msg == "There were 1 errors:\nThe migrations folder must be called \"migrations\""
    end

    test "sync migrations" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])

      {:success, msg} =
        Electric.Commands.Migrations.init(%{
          args: [],
          flags: [],
          options: %{:dir => temp},
          unknown: nil
        })

      assert File.exists?(migrations_path)
      assert msg == "Migrations initialised"

      sql_file_paths = Path.join([migrations_path, "*", "migration.sql"]) |> Path.wildcard()
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
          args: %{database_id: "1234"},
          flags: [],
          options: %{:dir => migrations_path},
          unknown: nil
        })

      assert msg == "Migrations synchronized with server successfully"
    end
  end
end
