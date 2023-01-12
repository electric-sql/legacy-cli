defmodule ElectricCli.Commands.Config do
  use ElectricCli, :command

  alias ElectricCli.Commands.Config.Init
  alias ElectricCli.Commands.Config.Update

  def spec do
    [
      name: "config",
      about: "Manage configuration of your ElectricSQL project",
      subcommands: [
        init: Init.spec(),
        update: Update.spec()
      ]
    ]
  end

  defdelegate init(opts), to: Init
  defdelegate update(opts), to: Update
end
