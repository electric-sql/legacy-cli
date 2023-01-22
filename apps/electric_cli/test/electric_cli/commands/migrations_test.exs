defmodule ElectricCli.Commands.MigrationsTest do
  use ElectricCli.CommandCase, async: false

  # alias ElectricCli.Config
  # alias ElectricCli.Config.Environment
  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration

  describe "electric migrations" do
    setup do
      [cmd: ["migrations"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Manage DDL schema migrations/
    end
  end

  describe "electric migrations new pre init" do
    setup do
      [cmd: ["migrations", "new"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Create a new migration/
    end

    test "returns error and shows usage if app id not specified", cxt do
      args = argv(cxt, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ ~r/Usage: /
    end

    test "returns error if run before electric init in this root", cxt do
      args = argv(cxt, ["create foos"])
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

    test "creates migration", cxt do
      args = argv(cxt, ["create foos"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "New migration created at:"

      assert [relative_file_path] =
               ~r/migrations\/.+_create_foos\/migration.sql/
               |> Regex.run(output)

      assert File.exists?(relative_file_path)
    end

    test "updates manifest", %{tmp_dir: root} = cxt do
      {:ok, %Manifest{migrations: migrations}} = load_manifest(root)
      assert Enum.count(migrations) == 1

      args = argv(cxt, ["create foos"])
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

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
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

    test "requires authentication"
    # , cxt do
    #   args = argv(cxt, [])
    #   assert {{:error, output}, _} = run_cmd(args)
    #   assert output =~ "electric auth login"
    # end
  end

  describe "electric migrations list post init" do
    setup :login
    setup :init

    setup do
      [cmd: ["migrations", "list"]]
    end

    test "lists initial migration"
    # , cxt do
    #   args = argv(cxt, [])
    #   assert {{:ok, output}, _} = run_cmd(args)
    #   assert output =~ "XXXXXXX"
    # end
  end

  describe "electric migrations list post build" do
    setup :login
    setup :init
    # setup :new_migration
    # setup :build

    setup do
      [cmd: ["migrations", "list"]]
    end

    test "lists as built"
    # , cxt do
    #   args = argv(cxt, [])
    #   assert {{:ok, output}, _} = run_cmd(args)
    #   assert output =~ "XXXXXXX"
    # end
  end

  describe "electric migrations list post sync" do
    setup :login
    setup :init
    # setup :new_migration
    # setup :build
    # setup :sync

    setup do
      [cmd: ["migrations", "list"]]
    end

    test "lists as synced"
    # , cxt do
    #   args = argv(cxt, [])
    #   assert {{:ok, output}, _} = run_cmd(args)
    #   assert output =~ "XXXXXXX"
    # end
  end
end
