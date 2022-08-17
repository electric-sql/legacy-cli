defmodule Electric.Commands.Auth do
  @moduledoc """
  The `Auth` command.
  """
  use Electric, :command

  def spec do
    [
      name: "auth",
      about: "Sign up, log in and manage authentication status.",
      flags: default_flags(),
      subcommands: [
        login: [
          name: "login",
          about: """
          Log in to Electric SQL.

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
          Log out of Electric SQL.

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
        perform_login(email, password)

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
        {:error, "failed to connect"}
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
    throw(:NotImplemented)
  end

  # *** Whoami ***

  def whoami(_cmd) do
    throw(:NotImplemented)
  end
end
