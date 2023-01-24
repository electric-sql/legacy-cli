defmodule ElectricCli.Commands.AuthTest do
  use ElectricCli.CommandCase, async: false

  describe "electric auth" do
    setup do
      [cmd: ["auth"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Log-in and manage authentication status/
    end
  end

  describe "electric auth login" do
    setup do
      [cmd: ["auth", "login"]]
    end

    test "shows help text if --help passed", ctx do
      args = argv(ctx, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Log in by email address./
    end

    test "requires email", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "missing required arguments: EMAIL"
    end

    test "log in with invalid credentials fails", ctx do
      args = argv(ctx, ["invalid@example.com", "--password", "wrong"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "invalid credentials"
    end

    test "log in with valid credentials works", ctx do
      args = argv(ctx, ["test@electric-sql.com", "--password", "password"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Logged in successfully as test@electric-sql.com"
    end
  end

  describe "electric auth logout when unauthenticated" do
    setup do
      [cmd: ["auth", "logout"]]
    end

    test "no-ops", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "You are logged out"
    end
  end

  describe "electric auth logout" do
    setup :login

    setup do
      [cmd: ["auth", "logout"]]
    end

    test "logs out", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Logged out successfully"
    end
  end

  describe "electric auth whoami when unauthenticated" do
    setup do
      [cmd: ["auth", "whoami"]]
    end

    test "logs out", ctx do
      args = argv(ctx, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "not logged in"
    end
  end

  describe "electric auth whoami" do
    setup :login

    setup do
      [cmd: ["auth", "whoami"]]
    end

    test "tells you who you are", ctx do
      args = argv(ctx, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "You are logged in as test@electric-sql.com"
    end
  end
end
