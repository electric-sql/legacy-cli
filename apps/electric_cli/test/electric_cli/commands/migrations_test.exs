defmodule ElectricCli.Commands.MigrationsTest do
  use ElectricCli.CommandCase, async: false

  alias ElectricCli.Config
  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration
  alias ElectricCli.Migrations

  describe "electric migrations" do
    setup do
      [cmd: ["migrations"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Manage DDL schema migrations/
    end
  end

  describe "electric migrations new pre init" do
    setup do
      [cmd: ["migrations", "new"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Create a new migration/
    end

    test "returns error and shows usage if app id not specified", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ ~r/Usage: /
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, ["create foos"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "file is missing in this directory"
    end
  end

  describe "electric migrations new" do
    setup :login
    setup :init

    setup do
      [cmd: ["migrations", "new"]]
    end

    test "creates migration", ctx do
      args = argv(ctx, ["create foos"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "New migration created at:"

      assert [relative_file_path] =
               ~r/migrations\/.+_create_foos\/migration.sql/
               |> Regex.run(output)

      assert File.exists?(relative_file_path)
    end

    test "updates manifest", %{tmp_dir: root} = ctx do
      {:ok, %Manifest{migrations: migrations}} = load_manifest(root)
      assert Enum.count(migrations) == 1

      args = argv(ctx, ["create foos"])
      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, %Manifest{migrations: migrations}} = load_manifest(root)
      assert Enum.count(migrations) == 2
      assert %Migration{title: "create foos"} = Enum.at(migrations, 1)
    end
  end

  describe "electric migrations list pre init" do
    setup do
      [cmd: ["migrations", "list"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Lists migrations/
    end
  end

  describe "electric migrations list unauthenticated" do
    setup :login
    setup :init
    setup :logout

    setup do
      [cmd: ["migrations", "list"]]
    end

    test "requires authentication", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "electric auth login"
    end
  end

  describe "electric migrations list post init" do
    setup :login
    setup :init

    setup do
      [cmd: ["migrations", "list"]]
    end

    test "lists initial migration", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Name\s+Title\s+Status/
      assert output =~ ~r/[0-9_]+_init\s+init\s+[-]/
    end
  end

  describe "electric migrations list new migration" do
    setup :login
    setup :init
    setup :new_migration

    setup do
      [cmd: ["migrations", "list"]]
    end

    test "lists both migrations still as unsynced", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/[0-9_]+_init\s+init\s+[-]/
      assert output =~ ~r/[0-9_]+_create_foos\s+create foos\s+[-]/
    end
  end

  describe "electric migrations revert pre init" do
    setup do
      [cmd: ["migrations", "revert"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/replace the local one/
    end
  end

  describe "electric migrations revert unauthenticated" do
    setup :login
    setup :init
    setup :logout

    setup do
      [cmd: ["migrations", "revert"]]
    end

    test "requires authentication", ctx do
      args = argv(ctx, ["some_name"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "electric auth login"
    end
  end

  describe "electric migrations revert" do
    setup(ctx) do
      ctx
      |> Map.put(:app, "test2")
    end

    setup :login
    setup :init

    setup do
      [cmd: ["migrations", "revert"]]
    end

    test "requires NAME or --all", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "specify a migration NAME or use the --all flag"
    end

    test "complains when missing", ctx do
      args = argv(ctx, ["not_a_migration"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "not found locally"
    end

    test "works when changed", %{tmp_dir: root} = ctx do
      assert {:ok, %Config{directories: %{migrations: migrations_dir}}} = Config.load(root)
      assert {:ok, %Manifest{migrations: migrations} = manifest} = load_manifest(root)
      assert [%Migration{name: current_name} = migration] = migrations

      # Hack a migration *not* matching the test2 fixture onto
      # the local filesystem.
      new_name = "second_migration_name"

      migration =
        migration
        |> Map.put(:name, new_name)

      assert :ok =
               manifest
               |> Map.put(:migrations, [migration])
               |> Manifest.save(migrations_dir)

      current_path = Path.join(migrations_dir, current_name)
      new_path = Path.join(migrations_dir, new_name)
      assert :ok = File.rename(current_path, new_path)

      # Now when we revert, it works.
      args = argv(ctx, [new_name])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Migration reverted successfully"
    end

    test "reports when unchanged", %{tmp_dir: root} = ctx do
      {:ok, %Config{directories: %{migrations: migrations_dir}}} = Config.load(root)
      {:ok, %Manifest{migrations: [%Migration{} = migration]} = manifest} = load_manifest(root)

      matching_name = "second_migration_name"
      matching_sha256 = "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad7"

      migration =
        migration
        |> Map.put(:name, matching_name)
        |> Map.put(:sha256, matching_sha256)

      :ok =
        manifest
        |> Map.put(:migrations, [migration])
        |> Manifest.save(migrations_dir)

      args = argv(ctx, [matching_name])

      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "Nothing to revert"
    end

    test "unless forced", %{tmp_dir: root} = ctx do
      {:ok, %Config{directories: %{migrations: migrations_dir}}} = Config.load(root)
      {:ok, %Manifest{migrations: [%Migration{} = migration]} = manifest} = load_manifest(root)

      matching_name = "second_migration_name"
      matching_sha256 = "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad7"

      migration =
        migration
        |> Map.put(:name, matching_name)
        |> Map.put(:sha256, matching_sha256)

      :ok =
        manifest
        |> Map.put(:migrations, [migration])
        |> Manifest.save(migrations_dir)

      args = argv(ctx, [matching_name, "--force"])

      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Migration reverted successfully"
    end
  end

  describe "electric migrations revert --all" do
    setup(ctx) do
      ctx
      |> Map.put(:app, "sync-from-1234")
    end

    setup :login
    setup :init

    setup do
      [cmd: ["migrations", "revert", "--all"]]
    end

    test "revert all", %{tmp_dir: root} = ctx do
      {:ok, %Config{directories: %{migrations: migrations_dir}}} = Config.load(root)

      args = argv(ctx, [])

      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Migrations reverted successfully"

      {:ok, %Manifest{} = manifest} = load_manifest(root)
      {:ok, %Manifest{} = manifest, []} = Migrations.hydrate_manifest(manifest, migrations_dir)

      Enum.each(manifest.migrations, fn %Migration{name: name, original_body: body} ->
        {:ok, contents} =
          [migrations_dir, name, "migration.sql"]
          |> Path.join()
          |> File.read()

        assert contents == body
      end)
    end
  end
end
