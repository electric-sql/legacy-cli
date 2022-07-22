defmodule ElectricTest do
  use ExUnit.Case
  doctest Electric

  test "entrypoint runs without error" do
    assert Electric.Main.main() == 0
  end
end
