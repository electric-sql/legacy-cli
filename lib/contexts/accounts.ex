defmodule Electric.Contexts.Accounts do
  @moduledoc """
  The `Accounts` context.
  """

  def spec do
    [
      name: "accounts",
      about: "Manage accounts",
      subcommands: [
        list: [
          name: "list",
          about: "List all the accounts",
          args: [
            # ...
          ]
        ]
      ]
    ]
  end

  def list(_cmd) do # flags: %{}, options: %{}, unknown: []}
    IO.inspect :list
  end
end
