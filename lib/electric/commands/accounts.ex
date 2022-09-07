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

          List all the accounts that you're a member of.
          """,
          flags: default_flags()
        ]
      ]
    ]
  end

  def list(_cmd) do
    result =
      Progress.run("Listing accounts", false, fn ->
        Client.get("accounts")
      end)

    case result do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:results, data}

      {:ok, %Req.Response{}} ->
        {:error, "invalid credentials"}

      {:error, _exception} ->
        {:error, "failed to connect"}
    end
  end
end
