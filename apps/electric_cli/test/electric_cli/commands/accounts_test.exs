defmodule ElectricCli.Commands.AccountsTest do
  use ElectricCli.CommandCase, async: false

  describe "electric accounts" do
    setup do
      [cmd: ["accounts"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Manage accounts/
    end
  end

  describe "electric accounts list unauthenticated" do
    setup do
      [cmd: ["accounts", "list"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/List your accounts/
    end

    test "requires authentication", cxt do
      args = argv(cxt, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "electric auth login"
    end
  end

  describe "electric accounts list" do
    setup :login

    setup do
      [cmd: ["accounts", "list"]]
    end

    test "lists accounts", cxt do
      args = argv(cxt, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/ID\s+Name/
      assert output =~ ~r/personal\s+Personal/
      assert output =~ ~r/work\s+Work/
    end
  end
end
