defmodule ElectricCli.Commands.ResetTest do
  use ElectricCli.CommandCase, async: false

  # alias ElectricCli.Config

  describe "electric reset unauthenticated" do
    setup do
      [cmd: ["reset"]]
    end

    test "requires authentication", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "Couldn't find ElectricSQL credentials"
    end
  end

  describe "electric reset pre init" do
    setup :login

    setup do
      [cmd: ["reset"]]
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

  describe "electric reset" do
    setup :login
    setup :init

    setup do
      [cmd: ["reset"]]
    end

    test "prompts for confirmation"
    test "resets"
    test "allows migrations to be re-synced"
  end
end
