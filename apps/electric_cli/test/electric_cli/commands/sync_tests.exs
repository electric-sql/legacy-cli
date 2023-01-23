defmodule ElectricCli.Commands.SyncTest do
  use ElectricCli.CommandCase, async: false

  alias ElectricCli.Bundle
  alias ElectricCli.Config

  describe "electric sync pre init" do
    setup do
      [cmd: ["sync"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Sync migrations upto the backend/
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "file is missing in this directory"
    end
  end

  describe "electric sync pre build" do
    setup :login
    setup :init

    setup do
      [cmd: ["sync"]]
    end

    test "sync works without running build first", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)

      assert output =~ "Synced 1 new migration"
    end
  end

  describe "electric sync" do
    setup :login
    setup :init
    setup :build

    setup do
      [cmd: ["sync"]]
    end

    test "syncs initial migration up", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)

      assert output =~ "Synced 1 new migration"
    end

    test "syncs new migrations up", ctx do
      new_migration(ctx)

      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)

      assert output =~ "Synced 2 new migrations"
    end

    test "rebuilds bundle using server data", %{tmp_dir: root} = ctx do
      assert {:ok, %Config{defaultEnv: env, directories: %{output: output_dir}}} =
               Config.load(root)

      bundle_path = Path.join(output_dir, "@config")
      assert {:ok, %Bundle{build: :local}} = Bundle.load(bundle_path)

      args = argv(ctx, [])
      assert {{:ok, _}, _} = run_cmd(args)

      assert {:ok, %Bundle{env: ^env}} = Bundle.load(bundle_path)
    end
  end

  describe "electric sync --env ENV" do
    setup :login
    setup :init
    setup :add_env
    setup :build

    setup do
      [cmd: ["sync"]]
    end

    test "syncs target environment", %{env: env, tmp_dir: root} = ctx do
      assert {:ok, %Config{directories: %{output: output_dir}}} = Config.load(root)

      args = argv(ctx, ["--env", env])
      assert {{:ok, _}, _} = run_cmd(args)

      bundle_path = Path.join([output_dir, "@app", env])
      assert {:ok, %Bundle{env: ^env}} = Bundle.load(bundle_path)
    end
  end
end