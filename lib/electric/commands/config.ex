defmodule Electric.Commands.Config do
  use Electric, :command

  alias Electric.Commands.Config.Init

  def spec do
    [
      name: "config",
      about: "Manage configuration of Electric project",
      subcommands: [
        init: Init.spec()
      ]
    ]
  end

  defdelegate init(opts), to: Init
end
