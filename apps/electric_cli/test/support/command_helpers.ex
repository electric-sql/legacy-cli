defmodule ElectricCli.Commands.CommandHelpers do
  @moduledoc """
  Helper and fixture-like functions for the command tests.
  """
  alias ElectricCli.Main
  alias ExUnit.CaptureIO

  def argv(%{cmd: cmd}, args) do
    cmd ++ args
  end

  def run_cmd(cmd) when is_binary(cmd) do
    cmd
    |> String.split()
    |> run_cmd()
  end

  def run_cmd(cmd) when is_list(cmd) do
    CaptureIO.with_io(fn -> Main.run(cmd) end)
  end
end
