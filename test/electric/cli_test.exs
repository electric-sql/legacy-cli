defmodule ElectricTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  doctest Electric

  test "entrypoint runs without error" do
    assert {{:halt, 0}, output} = with_io(fn -> Electric.run() end)

    assert output =~ "Electric SQL CLI"
  end
end
