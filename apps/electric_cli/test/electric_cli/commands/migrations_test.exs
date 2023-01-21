defmodule ElectricCli.Commands.MigrationsTest do
  use ElectricCli.CommandCase, async: false

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
