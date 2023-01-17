defmodule ElectricCli.Commands do
  @moduledoc """
  Default imports for a command.
  """

  def command do
    quote do
      import ElectricCli.Flags

      alias ElectricCli.Client
      alias ElectricCli.Password
      alias ElectricCli.Progress
      alias ElectricCli.Session
      alias ElectricCli.Util
    end
  end
end
