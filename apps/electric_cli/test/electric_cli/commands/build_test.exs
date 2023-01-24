defmodule ElectricCli.Commands.BuildTest do
  use ElectricCli.CommandCase, async: false

  alias ElectricCli.Bundle
  alias ElectricCli.Config
  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration

  describe "electric build pre init" do
    setup do
      [cmd: ["build"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Build your config and migrations/
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "file is missing in this directory"
    end
  end

  describe "electric build" do
    setup :login
    setup :init

    setup do
      [cmd: ["build"]]
    end

    test "succeeds", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Built successfully"
    end

    test "builds the index.js", %{tmp_dir: root} = ctx do
      {:ok, %Config{app: app, defaultEnv: env, directories: %{output: output_dir}}} =
        Config.load(root)

      index_js_file_path = Path.join([output_dir, app, env, "index.js"])
      assert not File.exists?(index_js_file_path)

      args = argv(ctx, [])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert File.exists?(index_js_file_path)
    end

    test "the index.js file is marked as a local build", %{tmp_dir: root} = ctx do
      args = argv(ctx, [])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{app: app, defaultEnv: env, directories: %{output: output_dir}}} =
               Config.load(root)

      assert {:ok, %Bundle{build: :local}} =
               [output_dir, app, env]
               |> Path.join()
               |> Bundle.load()
    end

    test "default manifest unchanged without flags", %{tmp_dir: root} = ctx do
      assert {:ok, %Manifest{migrations: migrations} = manifest} = load_manifest(root)
      assert [%Migration{satellite_body: [], postgres_body: nil}] = migrations

      args = argv(ctx, [])
      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, ^manifest} = load_manifest(root)
    end

    test "manifest updated with satellite flag", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--satellite"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Manifest{migrations: migrations}} = load_manifest(root)
      assert [%Migration{satellite_body: statements}] = migrations
      assert Enum.count(statements) > 0
    end

    test "manifest updated with postgres flag", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--postgres"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Manifest{migrations: migrations}} = load_manifest(root)
      assert [%Migration{postgres_body: postgres_body}] = migrations
      assert not is_nil(postgres_body)
    end

    test "can load index.js from @config alias", %{tmp_dir: root} = ctx do
      args = argv(ctx, [])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, %Bundle{}} =
               [output_dir, "@config"]
               |> Path.join()
               |> Bundle.load()
    end

    test "can load index.js from @app alias", %{tmp_dir: root} = ctx do
      args = argv(ctx, [])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{defaultEnv: default_env, directories: %{output: output_dir}}} =
               Config.load(root)

      assert {:ok, %Bundle{}} =
               [output_dir, "@app", default_env]
               |> Path.join()
               |> Bundle.load()
    end
  end

  describe "electric build --env ENV" do
    setup :login
    setup :init
    setup :add_env

    setup do
      [cmd: ["build"]]
    end

    test "target env must exist", ctx do
      args = argv(ctx, ["--env", "missing"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "not found"
    end

    test "builds for the target env", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--env", "staging"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{app: app, directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, %Bundle{}} =
               [output_dir, app, "staging"]
               |> Path.join()
               |> Bundle.load()
    end

    test "can load index.js from @app alias", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--env", "staging"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, %Bundle{}} =
               [output_dir, "@app", "staging"]
               |> Path.join()
               |> Bundle.load()
    end
  end
end
