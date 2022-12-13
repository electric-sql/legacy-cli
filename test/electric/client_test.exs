defmodule Electric.ClientTest do
  # don't run this simultaneously with other tests because messing with the env var may
  # break tests that use base_url/0
  use ExUnit.Case, async: false

  alias Electric.Client

  describe "base_url/0" do
    test "should default to the value given in compilation" do
      assert Client.base_url() == "http://localhost:4003/api/v1/"
    end

    test "should use the value from the environment if set" do
      try do
        System.put_env("ELECTRIC_BASE_URL", "https://base-url.electric-sql.com/api/v4/")
        assert Client.base_url() == "https://base-url.electric-sql.com/api/v4/"
      after
        System.delete_env("ELECTRIC_BASE_URL")
      end
    end
  end
end
