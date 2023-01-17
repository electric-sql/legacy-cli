defmodule ElectricCli.Commands.Config do
  use ElectricCli, :command

  alias ElectricCli.Commands.Config.Init

  def spec do
    [
      name: "config",
      about: "Manage configuration of ElectricSQL project",
      subcommands: [
        init: Init.spec()
      ]
    ]
  end

  defdelegate init(opts), to: Init
end
