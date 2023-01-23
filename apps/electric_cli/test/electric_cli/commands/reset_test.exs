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

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Reset your backend./
    end

    test "returns error if run before electric init in this root", ctx do
      args = argv(ctx, [])
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

    test "prompts for confirmation", ctx do
      args = argv(ctx, [])
      assert {{:ok, _output}, logged} = run_cmd(args)
      assert logged =~ "Are you sure you want to continue?"
    end

    test "resets", %{app: app} = ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _logged} = run_cmd(args)
      assert output =~ "Reset #{app}/default successfully"
    end

    test "allows migrations to be re-synced", ctx do
      args = argv(ctx, [])
      assert {{:ok, _output}, _} = run_cmd(args)

      assert {{:ok, output}, _} = run_cmd("sync")
      assert output =~ "Synced 1 new migration"
    end
  end
end
