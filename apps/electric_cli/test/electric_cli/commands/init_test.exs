defmodule ElectricCli.Commands.InitTest do
  use ElectricCli.CommandCase, async: false

  alias ElectricCli.Config
  alias ElectricCli.Config.Environment
  alias ElectricCli.Config.Replication
  alias ElectricCli.Manifest

  describe "electric init unauthenticated" do
    setup do
      [cmd: ["init"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/electric.json/
    end

    test "returns error and shows usage if app id not specified", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ ~r/Usage: /
    end

    test "requires authentication", ctx do
      args = argv(ctx, ["tarragon-envy-1337", "--verbose"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "electric auth login"
    end
  end

  describe "electric init" do
    setup :login

    setup do
      [cmd: ["init"]]
    end

    test "creates an electric.json file in the pwd", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["tarragon-envy-1337"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert_config(root, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: "migrations"
      })
    end

    test "warns on rerun", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["tarragon-envy-1337"])

      assert {{:ok, _output}, _} = run_cmd(args)
      assert {{:error, output}, _} = run_cmd(args)

      assert output =~ "project already initialised"
      assert output =~ "electric config update"

      assert_config(root, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: "migrations"
      })
    end

    test "can use a custom migrations directory", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--migrations-dir", "browser/migrations", "tarragon-envy-1337"])

      assert {{:ok, _output}, _} = run_cmd(args)

      assert_config(root, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: "browser/migrations"
      })
    end

    test "can use an absolute migrations directory", %{tmp_dir: root} = ctx do
      # I'm choosing to have the arg specify the full path to the migrations,
      # rather than point to the base and then add "migrations".

      migrations_dir =
        System.tmp_dir!()
        |> Path.join("/home/me/application/platform/my-migrations")

      on_exit(fn ->
        File.rm_rf!(migrations_dir)
      end)

      args = argv(ctx, ["--migrations-dir", migrations_dir, "tarragon-envy-1337"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert_config(root, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: migrations_dir
      })
    end

    test "allows for setting a custom default env", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--env", "prod", "tarragon-envy-1337"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert_config(root, %{
        app: "tarragon-envy-1337",
        env: "prod",
        migrations_dir: "migrations"
      })
    end

    test "by default replication data is empty", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["tarragon-envy-1337"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert %Environment{replication: nil} = Map.get(environments, :default)
    end

    test "sets replication data if provided", %{tmp_dir: root} = ctx do
      args =
        argv(ctx, [
          "tarragon-envy-1337",
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133",
          "--replication-disable-ssl"
        ])

      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert %Environment{replication: replication} = Map.get(environments, :default)
      assert %Replication{host: "localhost", port: 5133, ssl: false} = replication
    end

    test "creates manifest with one migration", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["tarragon-envy-1337"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{app: app, directories: %{migrations: migrations_dir}}} =
               Config.load(root)

      assert {:ok, %Manifest{migrations: migrations}} = Manifest.load(app, migrations_dir, false)

      assert Enum.count(migrations) == 1
    end

    test "sets @config symlink", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["tarragon-envy-1337"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok,
              %Config{
                app: app,
                defaultEnv: default_env,
                directories: %{output: output_dir}
              }} = Config.load(root)

      assert {:ok, link_target} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()

      assert link_target == Path.join(app, default_env)
    end

    test "sets @app symlink", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["tarragon-envy-1337"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{app: app, directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, ^app} =
               output_dir
               |> Path.join("@app")
               |> File.read_link()
    end
  end
end