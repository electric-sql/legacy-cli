defmodule ElectricCli.Commands.AppsTest do
  use ElectricCli.CommandCase, async: false

  describe "electric apps" do
    setup do
      [cmd: ["apps"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Manage backend applications/
    end
  end

  describe "electric apps list unauthenticated" do
    setup do
      [cmd: ["apps", "list"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/List your applications/
    end

    test "requires authentication", cxt do
      args = argv(cxt, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "electric auth login"
    end
  end

  describe "electric apps list" do
    setup :login

    setup do
      [cmd: ["apps", "list"]]
    end

    test "lists apps", cxt do
      args = argv(cxt, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/ID\s+Name\s+Environment\s+Status/
      assert output =~ "cranberry-soup-1337"
      assert output =~ "provisioned"
    end
  end

  describe "electric apps show" do
    setup :login

    setup do
      [cmd: ["apps", "show"]]
    end

    test "requires app", cxt do
      args = argv(cxt, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "missing required arguments: APP"
    end

    test "shows app", cxt do
      args = argv(cxt, ["tarragon-envy-1337"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/ID\s+Name\s+Environment\s+Status/
      assert output =~ "tarragon-envy-1337"
      assert output =~ "provisioned"
    end
  end
end
