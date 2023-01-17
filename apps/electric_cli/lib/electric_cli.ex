defmodule ElectricCli do
  @moduledoc """
  Documentation for `ElectricCli`.
  """

  @doc """
  Provide `use ElectricCli, :command`.
  """
  defmacro __using__(:command) do
    ElectricCli.Commands.command()
  end
end
