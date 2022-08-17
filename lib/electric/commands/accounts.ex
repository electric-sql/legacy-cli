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

  def list(_cmd) do
    case Client.get("accounts") do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:results, data}

      {:ok, %Req.Response{}} ->
        {:error, "invalid credentials"}

      {:error, _exception} ->
        {:error, "failed to connect"}
    end
  end
end
