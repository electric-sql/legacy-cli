defmodule Electric.Commands.Accounts do
  @moduledoc """
  The `Accounts` command.
  """
  alias Electric.Session
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
    with :ok <- Session.require_auth() do
      result =
        Progress.run("Listing accounts", false, fn ->
          Client.get("accounts")
        end)

      case result do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
          {:result,
           data
           |> Enum.map(&[IO.ANSI.green(), "* ", IO.ANSI.reset(), &1["name"]])
           |> Enum.join("\n")}

        {:ok, %Req.Response{status: 403}} ->
          {:error, "invalid credentials"}

        {:error, _exception} ->
          {:error, "couldn't connect to ElectricSQL servers"}
      end
    end
  end
end
