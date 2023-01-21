defmodule ElectricCli.Commands.SyncTest do
  use ElectricCli.CommandCase, async: false

  # alias ElectricCli.Config

  describe "electric sync pre init" do
    setup do
      [cmd: ["sync"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Reset your backend./
    end

    test "returns error if run before electric init in this root", cxt do
      args = argv(cxt, [])
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

    test "requires electric build", cxt do
      args = argv(cxt, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "XXXXXX"
    end

    test "requires electric build for target env"
  end

  describe "electric sync" do
    setup :login
    setup :init
    setup :build

    setup do
      [cmd: ["sync"]]
    end

    test "syncs local migrations up"
    test "syncs backend migrations down"
    test "syncs target environment"

    # If the app environment on your sync service already has a migration with the
    # same name but different sha256 then this sync will fail because a migration
    # cannot be modified once it has been applied.
    test "same name different sha256 fails"

    # The sync will also fail if the migration has a name that is lower in sort order
    # than one already applied on the server.
    test "earlier name fails"
  end
end
