defmodule ElectricCli.MainTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  doctest ElectricCli

  test "entrypoint runs without error" do
    assert {{:halt, 0}, output} = with_io(fn -> ElectricCli.Main.run() end)

    assert output =~ "ElectricSQL CLI"
  end
end
