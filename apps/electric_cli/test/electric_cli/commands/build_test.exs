defmodule ElectricCli.Commands.BuildTest do
  use ElectricCli.CommandCase, async: false

  # alias ElectricCli.Config

  describe "electric build pre init" do
    setup do
      [cmd: ["build"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Build your config and migrations/
    end

    test "returns error if run before electric init in this root", cxt do
      args = argv(cxt, [])
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

    test "updates the manifest"
    test "builds the index.js"
    test "index.js marked as built for local env"
    test "build for a target env"
    test "target env must exist"
  end
end
