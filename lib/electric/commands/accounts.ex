defmodule Electric.Commands.Accounts do
  @moduledoc """
  The `Accounts` command.
  """
  use Electric, :command

  def spec do
    [
      name: "accounts",
      about: "Manage accounts",
      subcommands: [
        list: [
          name: "list",
          about: """
          List your accounts.

          List all the accounts that the currently logged-in user
          is a member of.
          """,
          flags: default_flags()
        ]
      ]
    ]
  end

  # flags: %{}, options: %{}, unknown: []}
  def list(_cmd) do
    throw(:NotImplemented)
  end
end
