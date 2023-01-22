defmodule ElectricCli.Commands.CommandHelpers do
  @moduledoc """
  Helper and fixture-like functions for the command tests.
  """
  alias ExUnit.CaptureIO

  alias ElectricCli.Main

  alias ElectricCli.Config
  alias ElectricCli.Manifest

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

  def load_manifest(root) do
    with {:ok, %Config{app: app, directories: %{migrations: dir}}} <- Config.load(root) do
      Manifest.load(app, dir, false)
    end
  end
end
