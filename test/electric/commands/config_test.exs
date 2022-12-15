defmodule Electric.Commands.ConfigTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @capture_io true

  defp cd(path \\ File.cwd!(), action) when is_function(action, 0) do
    cwd = File.cwd!()

    try do
      File.cd!(path)
      if @capture_io, do: capture_io(action), else: action.()
    after
      File.cd!(cwd)
    end
  end

  defp assert_config(root, expected) do
    rc_file = Path.join(root, ".electricrc")
    assert File.exists?(rc_file)

    assert {:ok, config} = Jason.decode(File.read!(rc_file), keys: :atoms)

    assert config == expected

    # ensure that migrations directory exists and has been initialised
    assert File.dir?(expected.migrations_dir)

    migrations =
      Path.join(expected.migrations_dir, "*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    assert File.exists?(Path.join(expected.migrations_dir, "manifest.json"))

    # match on a length-1 array to assert that only one init migration has been created
    assert [init_migration] =
             Enum.filter(migrations, fn path -> Path.basename(path) =~ ~r/^[\d_]+_init/ end)

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
        assert {{:halt, 0}, output} = with_io(fn -> Electric.run(args) end)
        assert output =~ ~r/.electricrc/
      end

      test "returns error if app id not specified", cxt do
        args = argv(cxt, [])
        assert {{:halt, 1}, output} = with_io(fn -> Electric.run(args) end)
        assert output =~ ~r/.electricrc/
      end

      @tag :tmp_dir
      test "creates a .electricrc file in the pwd", cxt do
        args = argv(cxt, ["cranberry-soup-1337", "--verbose"])

        cd(cxt.tmp_dir, fn ->
          assert {:ok, _output} = Electric.run(args)
        end)

        assert_config(cxt.tmp_dir, %{
          root: cxt.tmp_dir,
          migrations_dir: Path.join(cxt.tmp_dir, "migrations"),
          app_id: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :tmp_dir
      test "should be idempotent", cxt do
        args = argv(cxt, ["cranberry-soup-1337", "--verbose"])

        cd(cxt.tmp_dir, fn ->
          assert {:ok, _output} = Electric.run(args)
        end)

        cd(cxt.tmp_dir, fn ->
          assert {:ok, _output} = Electric.run(args)
        end)

        assert_config(cxt.tmp_dir, %{
          root: cxt.tmp_dir,
          migrations_dir: Path.join(cxt.tmp_dir, "migrations"),
          app_id: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :tmp_dir
      test "should error if the existing migrations belong to another app", cxt do
        args1 = argv(cxt, ["cranberry-soup-1337", "--verbose"])

        cd(cxt.tmp_dir, fn ->
          assert {:ok, _output} = Electric.run(args1)
        end)

        args2 = argv(cxt, ["monkey-ears-9999", "--verbose"])

        cd(cxt.tmp_dir, fn ->
          assert {:error, _output} = Electric.run(args2)
        end)

        assert_config(cxt.tmp_dir, %{
          root: cxt.tmp_dir,
          migrations_dir: Path.join(cxt.tmp_dir, "migrations"),
          app_id: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :tmp_dir
      test "writes the config file to the specified root", cxt do
        args = argv(cxt, ["--dir", cxt.tmp_dir, "cranberry-soup-1337", "--verbose"])

        cd(fn ->
          assert {:ok, _output} = Electric.run(args)
        end)

        assert_config(cxt.tmp_dir, %{
          root: cxt.tmp_dir,
          migrations_dir: Path.join(cxt.tmp_dir, "migrations"),
          app_id: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :tmp_dir
      test "can use a custom migrations directory", cxt do
        args =
          argv(cxt, ["--migrations-dir", "browser/migrations", "cranberry-soup-1337", "--verbose"])

        cd(cxt.tmp_dir, fn ->
          assert {:ok, _output} = Electric.run(args)
        end)

        assert_config(cxt.tmp_dir, %{
          root: cxt.tmp_dir,
          migrations_dir: Path.join(cxt.tmp_dir, "browser/migrations"),
          app_id: "cranberry-soup-1337",
          env: "default"
        })
      end

      @tag :tmp_dir
      test "can use an absolute migrations directory", cxt do
        # I'm choosing to have the arg specify the full path to the migrations, rather than point
        # to the base and then we add "migrations".

        migrations_dir =
          Path.join(System.tmp_dir!(), "/home/me/application/platform/my-migrations")

        try do
          args =
            argv(cxt, ["--migrations-dir", migrations_dir, "cranberry-soup-1337", "--verbose"])

          cd(cxt.tmp_dir, fn ->
            assert {:ok, _output} = Electric.run(args)
          end)

          assert_config(cxt.tmp_dir, %{
            root: cxt.tmp_dir,
            migrations_dir: migrations_dir,
            app_id: "cranberry-soup-1337",
            env: "default"
          })
        after
          File.rm_rf!(migrations_dir)
        end
      end

      @tag :tmp_dir
      test "allows for setting a custom default env", cxt do
        args =
          argv(cxt, ["--dir", cxt.tmp_dir, "--env", "prod", "cranberry-soup-1337", "--verbose"])

        cd(fn ->
          assert {:ok, _output} = Electric.run(args)
        end)

        assert_config(cxt.tmp_dir, %{
          root: cxt.tmp_dir,
          migrations_dir: Path.join(cxt.tmp_dir, "migrations"),
          app_id: "cranberry-soup-1337",
          env: "prod"
        })
      end
    end
  end
end
