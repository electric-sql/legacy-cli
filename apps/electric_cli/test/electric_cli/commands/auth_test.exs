defmodule ElectricCli.Commands.AuthTest do
  use ElectricCli.CommandCase, async: false

  describe "electric auth" do
    setup do
      [cmd: ["auth"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Log-in and manage authentication status/
    end
  end

  describe "electric auth login" do
    setup do
      [cmd: ["auth", "login"]]
    end

    test "shows help text if --help passed", cxt do
      args = argv(cxt, ["--help"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ ~r/Log in by email address./
    end

    test "requires email", cxt do
      args = argv(cxt, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "missing required arguments: EMAIL"
    end

    test "log in with invalid credentials fails", cxt do
      args = argv(cxt, ["invalid@example.com", "--password", "wrong"])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "invalid credentials"
    end

    test "log in with valid credentials works", cxt do
      args = argv(cxt, ["test@electric-sql.com", "--password", "password"])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Logged in successfully as test@electric-sql.com"
    end
  end

  describe "electric auth logout when unauthenticated" do
    setup do
      [cmd: ["auth", "logout"]]
    end

    test "no-ops", cxt do
      args = argv(cxt, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "You are logged out"
    end
  end

  describe "electric auth logout" do
    setup :login

    setup do
      [cmd: ["auth", "logout"]]
    end

    test "logs out", cxt do
      args = argv(cxt, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "Logged out successfully"
    end
  end

  describe "electric auth whoami when unauthenticated" do
    setup do
      [cmd: ["auth", "whoami"]]
    end

    test "logs out", cxt do
      args = argv(cxt, [])
      assert {{:error, output}, _} = run_cmd(args)
      assert output =~ "not logged in"
    end
  end

  describe "electric auth whoami" do
    setup :login

    setup do
      [cmd: ["auth", "whoami"]]
    end

    test "tells you who you are", cxt do
      args = argv(cxt, [])
      assert {{:ok, output}, _} = run_cmd(args)
      assert output =~ "You are logged in as test@electric-sql.com"
    end
  end
end
