defmodule ElectricCli.Commands.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias ElectricCli.Util

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} = context do
    start_link_supervised!(ElectricCli.MockServer.spec())
    System.put_env("ELECTRIC_STATE_HOME", Path.join(dir, ".electric_credentials"))
    on_exit(fn -> System.delete_env("ELECTRIC_STATE_HOME") end)

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

    if context[:logout] do
      logout()
    end

    :ok
  end

  defp assert_config(root, expected) do
    rc_file = Path.join(root, "electric.json")
    migrations_dir = Path.expand(expected.migrations_dir, root)
    assert File.exists?(rc_file)

    assert %{} =
             config =
             File.read!(rc_file)
             |> Jason.decode!(keys: :atoms)
             |> Util.rename_map_key(:migrations, :migrations_dir)

    assert config == expected

    # ensure that migrations directory exists and has been initialised
    assert File.dir?(migrations_dir)

    migrations =
      Path.join(migrations_dir, "*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    assert File.exists?(Path.join(migrations_dir, "manifest.json"))

    # match on a length-1 array to assert that only one init migration has been created
    assert [init_migration] =
             migrations |> Enum.filter(fn path -> Path.basename(path) =~ ~r/^[\d_]+_init/ end)

    assert File.exists?(Path.join(init_migration, "migration.sql"))
  end

  def argv(cxt, args) do
    cxt.cmd ++ args
  end

  # both these commands do the same thing so test that
  commands = [["init"], ["config", "init"]]

  for cmd <- commands do
    describe "`electric #{Enum.join(cmd, " ")}`" do
      setup do
        {:ok, cmd: unquote(cmd)}
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

      test "Doesn't initialize the app if you're not logged in", cxt do
        on_exit(fn -> Application.put_env(:electric_cli, :verbose, false) end)

        args = argv(cxt, ["cranberry-soup-1337", "--verbose"])
        assert {{:error, output}, _} = with_io(fn -> ElectricCli.Main.run(args) end)
        assert output =~ "electric auth login <email>"
      end

      @tag :cd
      @tag :login
      test "creates an electric.json file in the pwd", cxt do
        args = argv(cxt, ["cranberry-soup-1337"])

        capture_io(fn ->
          assert {:ok, _output} = ElectricCli.Main.run(args)
        end)

        assert_config(cxt.tmp_dir, %{
          migrations_dir: "migrations",
          app: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :cd
      @tag :login
      test "should be idempotent", cxt do
        args = argv(cxt, ["cranberry-soup-1337"])

        assert {:ok, _output} = ElectricCli.Main.run(args)
        assert {:ok, _output} = ElectricCli.Main.run(args)

        assert_config(cxt.tmp_dir, %{
          migrations_dir: "migrations",
          app: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :cd
      @tag :login
      test "should error if the existing migrations belong to another app", cxt do
        args1 = argv(cxt, ["cranberry-soup-1337"])
        assert {:ok, _output} = ElectricCli.Main.run(args1)

        args2 = argv(cxt, ["test"])
        assert {:error, _output} = ElectricCli.Main.run(args2)

        assert_config(cxt.tmp_dir, %{
          migrations_dir: "migrations",
          app: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :cd
      @tag :login
      test "can use a custom migrations directory", cxt do
        args = argv(cxt, ["--migrations-dir", "browser/migrations", "cranberry-soup-1337"])
        assert {:ok, _output} = ElectricCli.Main.run(args)

        assert_config(cxt.tmp_dir, %{
          migrations_dir: "browser/migrations",
          app: "cranberry-soup-1337",
          env: "default"
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

        args = argv(cxt, ["--migrations-dir", migrations_dir, "cranberry-soup-1337"])

        assert {:ok, _output} = ElectricCli.Main.run(args)

        assert_config(cxt.tmp_dir, %{
          migrations_dir: migrations_dir,
          app: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :cd
      @tag :login
      test "allows for setting a custom default env", cxt do
        args = argv(cxt, ["--dir", cxt.tmp_dir, "--env", "prod", "cranberry-soup-1337"])

        assert {:ok, _output} = ElectricCli.Main.run(args)

        assert_config(cxt.tmp_dir, %{
          migrations_dir: "migrations",
          app: "cranberry-soup-1337",
          env: "prod"
        })
      end
    end
  end

  describe "`electric config update`" do
    setup do
      {:ok, cmd: unquote(["config", "update"])}
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {:ok, output} = ElectricCli.Main.run(args)
      assert output =~ ~r/electric.json/
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
      assert output =~ "electric auth login <email>"
    end

    @tag :cd
    @tag :login
    @tag :init
    test "unchanged says so", cxt do
      args = argv(cxt, ["--app", "cranberry-soup-1337"])
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
    test "updates the env", cxt do
      args = argv(cxt, ["--env", "staging"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        migrations_dir: "migrations",
        app: "cranberry-soup-1337",
        env: "staging"
      })
    end

    @tag :cd
    @tag :login
    @tag :init
    test "changes th migrations path", cxt do
      args = argv(cxt, ["--migrations-dir", "timbuktu"])

      capture_io(fn ->
        assert {:ok, _output} = ElectricCli.Main.run(args)
      end)

      assert_config(cxt.tmp_dir, %{
        migrations_dir: "timbuktu",
        app: "cranberry-soup-1337",
        env: "default"
      })
    end
  end

  defp init() do
    capture_io(fn ->
      assert {:ok, _} = ElectricCli.Main.run(~w|init cranberry-soup-1337|)
    end)
  end

  defp login() do
    capture_io(fn ->
      assert {:ok, _} =
               ElectricCli.Main.run(~w|auth login test@electric-sql.com --password password|)
    end)
  end

  defp logout() do
    capture_io(fn ->
      assert {:ok, _} = ElectricCli.Main.run(~w|auth logout|)
    end)
  end
end
