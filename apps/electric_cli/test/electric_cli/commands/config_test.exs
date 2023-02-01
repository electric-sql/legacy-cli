defmodule ElectricCli.Commands.ConfigTest do
  use ElectricCli.CommandCase, async: false

  alias ElectricCli.Config
  alias ElectricCli.Config.Console
  alias ElectricCli.Config.Environment
  alias ElectricCli.Config.Replication

  describe "electric config" do
    setup do
      [cmd: ["config"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Manage local configuration/
    end
  end

  describe "electric config update pre init" do
    setup do
      [cmd: ["config", "update"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Update your configuration/
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "file is missing in this directory"
    end
  end

  describe "electric config update unauthenticated" do
    setup [
      :login,
      :init,
      :logout
    ]

    setup do
      [cmd: ["config", "update"]]
    end

    test "doesn't update the app if you're not logged in", ctx do
      args = argv(ctx, ["--app", "french-onion-1234"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "electric auth login"
    end
  end

  describe "electric config update" do
    setup [
      :login,
      :init
    ]

    setup do
      [cmd: ["config", "update"]]
    end

    test "unchanged says so", ctx do
      args = argv(ctx, ["--app", "tarragon-envy-1337"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Nothing to update"
    end

    test "updates the app", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--app", "french-onion-1234"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert_config(root, %{
        migrations_dir: "migrations",
        app: "french-onion-1234",
        env: "default"
      })
    end

    test "setting app updates @app symlink", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--app", "french-onion-1234"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, "french-onion-1234"} =
               output_dir
               |> Path.join("@app")
               |> File.read_link()
    end

    test "setting app updates @app symlink even when not changed", %{tmp_dir: root} = ctx do
      filepath = Path.join(root, "electric.json")

      :ok =
        filepath
        |> File.read!()
        |> String.replace("tarragon-envy-1337", "french-onion-1234")
        |> then(&File.write(filepath, &1))

      assert {:ok, %Config{app: "french-onion-1234", directories: %{output: output_dir}}} =
               Config.load(root)

      assert {:ok, "tarragon-envy-1337"} =
               output_dir
               |> Path.join("@app")
               |> File.read_link()

      args = argv(ctx, ["--app", "french-onion-1234"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Nothing to update"

      assert {:ok, "french-onion-1234"} =
               output_dir
               |> Path.join("@app")
               |> File.read_link()

      assert {:ok, "french-onion-1234/default"} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()
    end

    test "env must exists when updating the default env", ctx do
      args = argv(ctx, ["--env", "staging"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "env `staging` not found"
      assert output =~ "electric config add_env"
    end

    test "updates default env", %{tmp_dir: root} = ctx do
      %{env: env} = add_env(ctx)

      args = argv(ctx, ["--env", env])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert_config(root, %{
        migrations_dir: "migrations",
        app: "tarragon-envy-1337",
        env: env
      })
    end

    test "setting app updates @app and @config symlinks", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--app", "lala-som-1234"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {:ok, %Config{app: app, defaultEnv: env, directories: %{output: output_dir}}} =
               Config.load(root)

      assert {:ok, ^app} =
               output_dir
               |> Path.join("@app")
               |> File.read_link()

      assert {:ok, link_target} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()

      assert link_target == Path.join(app, env)
    end

    test "setting env updates @config symlink", %{tmp_dir: root} = ctx do
      %{env: env} = add_env(ctx)

      args = argv(ctx, ["--env", env])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{app: app, directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, link_target} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()

      assert link_target == Path.join(app, env)
    end

    test "changes the migrations path", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["--migrations-dir", "timbuktu"])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert_config(root, %{
        migrations_dir: "timbuktu",
        app: "tarragon-envy-1337",
        env: "default"
      })
    end

    test "sets console data if provided", %{tmp_dir: root} = ctx do
      args =
        argv(ctx, [
          "--console-disable-ssl",
          "--console-host",
          "localhost",
          "--console-port",
          "8080"
        ])

      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, %Config{environments: %{default: %Environment{} = environment}}} = Config.load(root)
      assert %{console: %Console{host: "localhost", port: 8080, ssl: false}} = environment
    end

    test "sets replication data if provided", %{tmp_dir: root} = ctx do
      args =
        argv(ctx, [
          "--replication-disable-ssl",
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133"
        ])

      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, %Config{environments: %{default: %Environment{} = environment}}} = Config.load(root)
      assert %{replication: %Replication{host: "localhost", port: 5133, ssl: false}} = environment
    end
  end

  describe "electric config add_env pre init" do
    setup do
      [cmd: ["config", "add_env"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Add a new environment/
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, ["some-env"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "file is missing in this directory"
    end
  end

  describe "electric config add_env" do
    setup [
      :login,
      :init
    ]

    setup do
      [cmd: ["config", "add_env"]]
    end

    test "errors if env already exists", ctx do
      args = argv(ctx, ["default"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "already exists"
    end

    test "adds the env", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{environments: %{staging: %Environment{}}}} = Config.load(root)
    end

    test "defaults to not setting as default", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{defaultEnv: default_env}} = Config.load(root)
      assert default_env != "staging"
    end

    test "sets as default if instructed", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging", "--set-as-default"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{defaultEnv: "staging"}} = Config.load(root)
    end

    test "doesn't updates @config symlink if not set as default", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{app: app, directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, link_target} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()

      assert link_target != Path.join(app, "staging")
    end

    test "updates @config symlink if set as default", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging", "--set-as-default"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{app: app, directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, link_target} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()

      assert link_target == Path.join(app, "staging")
    end

    test "sets console data if provided", %{tmp_dir: root} = ctx do
      args =
        argv(ctx, [
          "staging",
          "--console-disable-ssl",
          "--console-host",
          "localhost",
          "--console-port",
          "8080"
        ])

      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, %Config{environments: %{staging: %Environment{} = environment}}} = Config.load(root)
      assert %{console: %Console{host: "localhost", port: 8080, ssl: false}} = environment
    end

    test "sets replication data if provided", %{tmp_dir: root} = ctx do
      args =
        argv(ctx, [
          "staging",
          "--replication-disable-ssl",
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133"
        ])

      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, %Config{environments: %{staging: %Environment{} = environment}}} = Config.load(root)
      assert %{replication: %Replication{host: "localhost", port: 5133, ssl: false}} = environment
    end
  end

  describe "electric config update_env pre init" do
    setup do
      [cmd: ["config", "update_env"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Update the configuration of an environment/
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, ["some-env"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "file is missing in this directory"
    end
  end

  describe "electric config update_env" do
    setup [
      :login,
      :init
    ]

    setup do
      [cmd: ["config", "update_env"]]
    end

    test "errors if env does not exist", ctx do
      args = argv(ctx, ["staging"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "not found"
    end

    test "sets console data if provided", %{tmp_dir: root} = ctx do
      args =
        argv(ctx, [
          "default",
          "--console-disable-ssl",
          "--console-host",
          "localhost",
          "--console-port",
          "8080"
        ])

      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, %Config{environments: %{default: %Environment{} = environment}}} = Config.load(root)
      assert %{console: %Console{host: "localhost", port: 8080, ssl: false}} = environment
    end

    test "sets replication data if provided", %{tmp_dir: root} = ctx do
      args =
        argv(ctx, [
          "default",
          "--replication-disable-ssl",
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133"
        ])

      assert {{:ok, _output}, _} = run_cmd(args)

      {:ok, %Config{environments: %{default: %Environment{} = environment}}} = Config.load(root)
      assert %{replication: %Replication{host: "localhost", port: 5133, ssl: false}} = environment
    end
  end

  describe "electric config update_env --set-as-default" do
    setup [
      :login,
      :init,
      :add_env
    ]

    setup do
      [cmd: ["config", "update_env"]]
    end

    test "defaults to not setting as default", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{defaultEnv: default_env}} = Config.load(root)
      assert default_env != "staging"
    end

    test "sets as default if instructed", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging", "--set-as-default"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{defaultEnv: "staging"}} = Config.load(root)
    end

    test "doesn't updates @config symlink if not set as default", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{app: app, directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, link_target} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()

      assert link_target != Path.join(app, "staging")
    end

    test "updates @config symlink if set as default", %{tmp_dir: root} = ctx do
      args = argv(ctx, ["staging", "--set-as-default"])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{app: app, directories: %{output: output_dir}}} = Config.load(root)

      assert {:ok, link_target} =
               output_dir
               |> Path.join("@config")
               |> File.read_link()

      assert link_target == Path.join(app, "staging")
    end
  end

  describe "electric config remove_env pre init" do
    setup do
      [cmd: ["config", "remove_env"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Remove an environment/
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, ["some-env"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "file is missing in this directory"
    end
  end

  describe "electric config remove_env invalid" do
    setup [
      :login,
      :init
    ]

    setup do
      [cmd: ["config", "remove_env"]]
    end

    test "errors if env does not exist", ctx do
      args = argv(ctx, ["staging"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "not found"
    end

    test "errors if env is the default env", ctx do
      args = argv(ctx, ["default"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "can't remove your default env."
    end
  end

  describe "electric config remove_env" do
    setup [
      :login,
      :init,
      :add_env
    ]

    setup do
      [cmd: ["config", "remove_env"]]
    end

    test "can't remove the env if added as default", %{env: env} = ctx do
      set_default_env(%{default_env: env})

      args = argv(ctx, [env])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "can't remove your default env."
    end

    test "removes env", %{env: env, tmp_dir: root} = ctx do
      args = argv(ctx, [env])
      assert {{:ok, _output}, _} = run_cmd(args)
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert not Map.has_key?(environments, String.to_existing_atom(env))
    end
  end
end
