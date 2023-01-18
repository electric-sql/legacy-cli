defmodule ElectricCli.Commands do
  @moduledoc """
  Default imports for a command.
  """

  def command do
    quote do
      import ElectricCli.Options
      import ElectricCli.Util, only: [verbose: 1]

      alias ElectricCli.Client
      alias ElectricCli.Config
      alias ElectricCli.Password
      alias ElectricCli.Progress
      alias ElectricCli.Session
      alias ElectricCli.Util
    end
  end
end
