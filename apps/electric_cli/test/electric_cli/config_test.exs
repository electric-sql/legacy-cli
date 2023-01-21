defmodule ElectricCli.Commands.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias ElectricCli.Config

  alias ElectricCli.Config.{
    Environment,
    Replication
  }

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} = context do
    start_link_supervised!(ElectricCli.MockServer.spec())

    System.put_env("ELECTRIC_STATE_HOME", Path.join(dir, ".electric_credentials"))

    on_exit(fn ->
      File.rm_rf!(dir)
      System.delete_env("ELECTRIC_STATE_HOME")
    end)

    if context[:cd] do
      saved = File.cwd!()
      File.cd!(dir)
      on_exit(fn -> File.cd!(saved) end)
    end

    if context[:login] do
      login()
    end

    if context[:init] do
      init()
    end

    if context[:add_staging_env] do
      add_staging_env()
    end

    if context[:set_staging_default] do
      set_staging_default()
    end

    if context[:logout] do
      logout()
    end

    :ok
  end

  defp assert_config(root, expected) do
    assert {:ok, %Config{directories: directories} = config} = Config.load(root)

    # IO.inspect(config)

    assert expected.app == config.app
    assert expected.env == config.defaultEnv

    directories = Config.contract_directories(directories, root)
    assert expected.migrations_dir == directories.migrations

    migrations_dir = Path.expand(directories.migrations, root)
    assert File.dir?(migrations_dir)

    migrations =
      Path.join(migrations_dir, "*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    assert File.exists?(Path.join(migrations_dir, "manifest.json"))

    # match on a length-1 array to assert that only one init migration has been created
    assert [init_migration] =
             migrations
             |> Enum.filter(fn path -> Path.basename(path) =~ ~r/^[\d_]+_init/ end)

    assert File.exists?(Path.join(init_migration, "migration.sql"))
  end

  def argv(%{cmd: cmd}, ["--help"]) do
    cmd ++ ["--help"]
  end

  def argv(%{tmp_dir: root, cmd: cmd}, args) do
    cmd ++ args ++ ["--root", root]
  end

  describe "electric init" do
    setup do
      {:ok, cmd: ["init"]}
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])

      assert {:ok, output} = ElectricCli.Main.run(args)
      assert output =~ ~r/electric.json/
    end

    test "returns error and shows usage if app id not specified", cxt do
      args = argv(cxt, [])
      assert {:error, output} = ElectricCli.Main.run(args)
      assert output =~ ~r/Usage: /
    end

    @tag :cd
    @tag :login
    @tag :logout
    test "Doesn't initialize the app if you're not logged in", cxt do
      args = argv(cxt, ["tarragon-envy-1337", "--verbose"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "electric auth login"
    end

    @tag :cd
    @tag :login
    test "creates an electric.json file in the pwd", cxt do
      args = argv(cxt, ["tarragon-envy-1337"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: "migrations"
      })
    end

    @tag :cd
    @tag :login
    test "warns on rerun", cxt do
      args = argv(cxt, ["tarragon-envy-1337"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
        assert {:error, output} = ElectricCli.Main.run(args)

        assert output =~ "project already initialised"
        assert output =~ "electric config update"
      end)

      assert_config(cxt.tmp_dir, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: "migrations"
      })
    end

    @tag :cd
    @tag :login
    test "can use a custom migrations directory", cxt do
      args = argv(cxt, ["--migrations-dir", "browser/migrations", "tarragon-envy-1337"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: "browser/migrations"
      })
    end

    @tag :cd
    @tag :login
    test "can use an absolute migrations directory", cxt do
      # I'm choosing to have the arg specify the full path to the migrations, rather than point
      # to the base and then we add "migrations".

      migrations_dir =
        Path.join([System.tmp_dir!(), "/home/me/application/platform/my-migrations"])

      on_exit(fn -> File.rm_rf!(migrations_dir) end)

      args = argv(cxt, ["--migrations-dir", migrations_dir, "tarragon-envy-1337"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        app: "tarragon-envy-1337",
        env: "default",
        migrations_dir: migrations_dir
      })
    end

    @tag :cd
    @tag :login
    test "allows for setting a custom default env", cxt do
      args = argv(cxt, ["--env", "prod", "tarragon-envy-1337"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        app: "tarragon-envy-1337",
        env: "prod",
        migrations_dir: "migrations"
      })
    end

    @tag :cd
    @tag :login
    test "by default replication data is empty", cxt do
      args = argv(cxt, ["tarragon-envy-1337"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      root = cxt.tmp_dir
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert %Environment{replication: nil} = Map.get(environments, :default)
    end

    @tag :cd
    @tag :login
    test "sets replication data if provided", cxt do
      args =
        argv(cxt, [
          "tarragon-envy-1337",
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133",
          "--replication-disable-ssl"
        ])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      root = cxt.tmp_dir
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert %Environment{replication: replication} = Map.get(environments, :default)
      assert %Replication{host: "localhost", port: 5133, ssl: false} = replication
    end
  end

  describe "electric config update" do
    setup do
      {:ok, cmd: ["config", "update"]}
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {:ok, output} = ElectricCli.Main.run(args)
      assert output =~ ~r/Update your configuration/
    end

    test "returns error if run before electric init in this root", cxt do
      args = argv(cxt, [])
      assert {:error, output} = ElectricCli.Main.run(args)
      assert output =~ "file is missing in this directory"
    end

    @tag :cd
    @tag :login
    @tag :init
    @tag :logout
    test "doesn't update the app if you're not logged in", cxt do
      args = argv(cxt, ["--app", "french-onion-1234"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "electric auth login EMAIL"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "unchanged says so", cxt do
      args = argv(cxt, ["--app", "tarragon-envy-1337"])
      assert {{:ok, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "Nothing to update"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "updates the app", cxt do
      args = argv(cxt, ["--app", "french-onion-1234"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        migrations_dir: "migrations",
        app: "french-onion-1234",
        env: "default"
      })
    end

    @tag :cd
    @tag :login
    @tag :init
    test "env must exists when updating the default env", cxt do
      args = argv(cxt, ["--env", "staging"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "env `staging` not found"
      assert output =~ "electric config add_env"
    end

    @tag :cd
    @tag :login
    @tag :init
    @tag :add_staging_env
    test "updates default env", cxt do
      args = argv(cxt, ["--env", "staging"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        migrations_dir: "migrations",
        app: "tarragon-envy-1337",
        env: "staging"
      })
    end

    @tag :cd
    @tag :login
    @tag :init
    test "changes the migrations path", cxt do
      args = argv(cxt, ["--migrations-dir", "timbuktu"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        migrations_dir: "timbuktu",
        app: "tarragon-envy-1337",
        env: "default"
      })
    end

    @tag :cd
    @tag :login
    @tag :init
    test "sets replication data if provided", cxt do
      args =
        argv(cxt, [
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133",
          "--replication-disable-ssl"
        ])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      root = cxt.tmp_dir
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert %Environment{replication: replication} = Map.get(environments, :default)
      assert %Replication{host: "localhost", port: 5133, ssl: false} = replication
    end
  end

  describe "electric config add_env" do
    setup do
      {:ok, cmd: ["config", "add_env"]}
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {:ok, output} = ElectricCli.Main.run(args)
      assert output =~ ~r/Add a new environment/
    end

    test "returns error if run before electric init in this root", cxt do
      args = argv(cxt, ["some-env"])
      assert {:error, output} = ElectricCli.Main.run(args)
      assert output =~ "file is missing in this directory"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "errors if env already exists", cxt do
      args = argv(cxt, ["default"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "already exists"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "adds the env", cxt do
      args = argv(cxt, ["staging"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      root = cxt.tmp_dir
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert Map.has_key?(environments, :staging)
    end

    @tag :cd
    @tag :login
    @tag :init
    test "sets replication data if provided", cxt do
      args =
        argv(cxt, [
          "staging",
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133",
          "--replication-disable-ssl"
        ])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      root = cxt.tmp_dir
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert %Environment{replication: replication} = Map.get(environments, :staging)
      assert %Replication{host: "localhost", port: 5133, ssl: false} = replication
    end
  end

  describe "electric config update_env" do
    setup do
      {:ok, cmd: ["config", "update_env"]}
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {:ok, output} = ElectricCli.Main.run(args)
      assert output =~ ~r/Update the configuration of an environment/
    end

    test "returns error if run before electric init in this root", cxt do
      args = argv(cxt, ["some-env"])
      assert {:error, output} = ElectricCli.Main.run(args)
      assert output =~ "file is missing in this directory"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "errors if env does not exist", cxt do
      args = argv(cxt, ["staging"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "not found"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "sets replication data if provided", cxt do
      args =
        argv(cxt, [
          "default",
          "--replication-host",
          "localhost",
          "--replication-port",
          "5133",
          "--replication-disable-ssl"
        ])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      root = cxt.tmp_dir
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert %Environment{replication: replication} = Map.get(environments, :default)
      assert %Replication{host: "localhost", port: 5133, ssl: false} = replication
    end
  end

  describe "electric config remove_env" do
    setup do
      {:ok, cmd: ["config", "remove_env"]}
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {:ok, output} = ElectricCli.Main.run(args)
      assert output =~ ~r/Remove an environment/
    end

    test "returns error if run before electric init in this root", cxt do
      args = argv(cxt, ["some-env"])
      assert {:error, output} = ElectricCli.Main.run(args)
      assert output =~ "file is missing in this directory"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "errors if env does not exist", cxt do
      args = argv(cxt, ["staging"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "not found"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "errors if env is the default env", cxt do
      args = argv(cxt, ["default"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "can't remove your default env."
    end

    @tag :cd
    @tag :login
    @tag :init
    @tag :add_staging_env
    @tag :set_staging_default
    test "even if the default env has been set", cxt do
      args = argv(cxt, ["staging"])
      assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
      assert output =~ "can't remove your default env."
    end

    @tag :cd
    @tag :login
    @tag :init
    @tag :add_staging_env
    test "removes env", cxt do
      args = argv(cxt, ["staging"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      root = cxt.tmp_dir
      assert {:ok, %Config{environments: environments}} = Config.load(root)
      assert not Map.has_key?(environments, :staging)
    end
  end
end
