defmodule ElectricCli.Commands.Auth do
  @moduledoc """
  The `Auth` command.
  """
  use ElectricCli, :command

  def spec do
    [
      name: "auth",
      about: "Log-in and manage authentication status.",
      flags: default_flags(),
      subcommands: [
        login: [
          name: "login",
          about: """
          Log in to ElectricSQL.

          Log in by email address. Prompts for a password if not provided.
          """,
          args: [
            email: [
              value_name: "EMAIL",
              help: "Your email address",
              required: true,
              parser: :string
            ]
          ],
          options: [
            password: [
              value_name: "**********",
              short: "-p",
              long: "--password",
              help: "Your password",
              parser: :string,
              required: false
            ]
          ],
          flags: default_flags()
        ],
        logout: [
          name: "logout",
          about: """
          Log out of ElectricSQL.

          Clears your local authentication token.
          """,
          flags: default_flags()
        ],
        whoami: [
          name: "whoami",
          about: """
          See who you're logged-in as.
          """,
          flags: default_flags()
        ]
      ]
    ]
  end

  # *** Login ***

  def login(%{args: %{email: email}, options: %{password: password}}) do
    case handle_password(password) do
      {:ok, password} ->
        Progress.run("Authenticating", fn ->
          perform_login(email, password)
        end)

      _ ->
        {:error, "failed to read password"}
    end
  end

  defp handle_password(nil) do
    "Enter your password:"
    |> Password.get_password()
    |> String.trim()
    |> handle_password()
  end

  defp handle_password(password) when is_binary(password) do
    {:ok, password}
  end

  defp perform_login(email, password) do
    path = "/auth/login"

    payload = %{
      data: %{
        email: email,
        password: password
      }
    }

    case Client.post(path, payload) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        handle_login_response(data)

      {:ok, %Req.Response{}} ->
        {:error, "invalid credentials"}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  defp handle_login_response(%{"email" => email} = data) do
    data
    |> Util.rename_map_key("refreshToken", "refresh_token")
    |> Session.set()
    |> case do
      :ok ->
        {:success, "Logged in successfully as #{email}"}

      _ ->
        {:error, "failed to store authentication token"}
    end
  end

  # *** Logout ***

  def logout(_cmd) do
    case Session.clear() do
      :ok ->
        {:success, "Logged out successfully"}

      {:error, :enoent} ->
        {:success, "You are logged out"}

      _ ->
        {:error, "failed to clear authentication token"}
    end
  end

  # *** Whoami ***

  def whoami(_cmd) do
    case Session.get() do
      %Session.Credentials{email: email} ->
        {:result, "You are logged in as #{email}"}

      nil ->
        {:error, "you're not logged in"}
    end
  end
end
