defmodule ElectricCli.ClientTest do
  # don't run this simultaneously with other tests because messing with the env var may
  # break tests that use base_url/0
  use ExUnit.Case, async: false

  alias ElectricCli.Client

  describe "base_url/0" do
    test "should default to the value given in compilation" do
      default_url = Application.fetch_env!(:electric_cli, :default_console_url)

      assert Client.base_url() == default_url <> "/api/v1/"
    end

    test "should use the value from the environment if set" do
      try do
        System.put_env("ELECTRIC_CONSOLE_URL", "https://base-url.electric-sql.com")

        assert Client.base_url() == "https://base-url.electric-sql.com/api/v1/"
      after
        System.delete_env("ELECTRIC_CONSOLE_URL")
      end
    end
  end
end
