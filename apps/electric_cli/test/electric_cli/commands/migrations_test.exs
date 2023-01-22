defmodule ElectricCli.Commands.MigrationsTest do
  use ElectricCli.CommandCase, async: false

  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration

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

  # describe "electric migrations list post sync" do
  #   setup(ctx) do
  #     ctx
  #     |> Map.put(:app, "app-name-2")
  #   end

  #   setup :login
  #   setup :init

  #   setup do
  #     [cmd: ["migrations", "list"]]
  #   end

  #   test "lists as applied", ctx do
  #     args = argv(ctx, [])
  #     assert {{:ok, output}, _} = run_cmd(args)
  #     assert output =~ ~r/1666612306_test_migration\s+test migration\s+applied/
  #   end
  # end
end
