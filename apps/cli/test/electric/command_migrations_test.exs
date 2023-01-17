defmodule Electric.Command.MigrationsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Electric.Config

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, _pid} = start_supervised(Electric.MockServer.spec())
    System.put_env("ELECTRIC_STATE_HOME", Path.join(tmp_dir, ".electric_credentials"))
    on_exit(fn -> System.delete_env("ELECTRIC_STATE_HOME") end)

    capture_io(fn ->
      assert {:ok, _} = Electric.run(~w|auth login test@electric-sql.com --password password|)
    end)

    :ok
  end

  describe "run commands" do
    setup %{tmp_dir: tmp_dir} do
      config =
        Config.new(
          root: tmp_dir,
          migrations_dir: "./migrations",
          app_id: "cranberry-soup-1337",
          env: "default"
        )

      # create migrations dir
      {:ok, _path} = Config.init(config)

      sql_file_paths =
        [Path.expand(config.migrations_dir, config.root), "*", "migration.sql"]
        |> Path.join()
        |> Path.wildcard()

      {:ok, config: config, sql_paths: sql_file_paths}
    end

    test "build migrations", %{config: config, sql_paths: sql_file_paths} do
      my_new_migration = List.first(sql_file_paths)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      capture_io(fn ->
        assert {:success, _msg} =
                 Electric.Commands.Migrations.build(%{
                   args: [],
                   flags: [],
                   options: %{root: config.root},
                   unknown: nil
                 })
      end)

      assert Path.expand(config.migrations_dir, config.root)
             |> Path.join("manifest.json")
             |> File.exists?()
    end

    test "sync migrations", %{config: config, sql_paths: sql_file_paths} do
      my_new_migration = List.first(sql_file_paths)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      capture_io(fn ->
        assert {:success, msg} =
                 Electric.Commands.Migrations.sync(%{
                   args: %{},
                   flags: [],
                   options: %{root: config.root, env: "production"},
                   unknown: nil
                 })

        assert msg == "Migrations synchronized with server successfully"
      end)
    end

    test "new migrations", %{config: config, sql_paths: sql_file_paths} do
      my_new_migration = List.first(sql_file_paths)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      capture_io(fn ->
        {:success, msg} =
          Electric.Commands.Migrations.new(%{
            args: %{migration_title: "Another migration"},
            flags: [],
            options: %{root: config.root},
            unknown: nil
          })

        assert msg =~ ~r/^New migration created/
      end)
    end

    test "list migrations", %{config: config, sql_paths: sql_file_paths} do
      my_new_migration = List.first(sql_file_paths)
      migration_name = Path.dirname(my_new_migration) |> Path.basename()

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      capture_io(fn ->
        {:success, msg} =
          Electric.Commands.Migrations.list(%{
            args: %{},
            flags: [],
            options: %{root: config.root},
            unknown: nil
          })

        assert strip_colors(msg) == """

               ------ Electric SQL Migrations ------

               #{migration_name}\tdefault: -
               """
      end)
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

      capture_io(fn ->
        {:error, msg} =
          Electric.Commands.Migrations.revert(%{
            args: %{migration_name: migration_name},
            flags: [],
            options: %{root: config.root, env: "default"},
            unknown: nil
          })

        assert msg ==
                 """
                 There was 1 errors:
                 The migration #{migration_name} in environment default is not different. Nothing to revert.
                 """
                 |> String.trim()
      end)
    end
  end

  @ansi_regex ~r/(\x9B|\x1B\[)[0-?]*[ -\/]*[@-~]/
  defp strip_colors(string) when is_binary(string) do
    Regex.replace(@ansi_regex, string, "")
  end
end
