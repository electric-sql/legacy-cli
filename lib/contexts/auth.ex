defmodule Electric.Contexts.Auth do
  @moduledoc """
  The `Auth` context.
  """

  def spec do
    [
      name: "auth",
      about: "Sign up, log in and manage authentication status.",
      flags: [
        help: [
          long: "--help",
          help: "Print usage docs",
          required: false
        ],
      ],
      subcommands: [
        login: [
          name: "login",
          about: """
          Log in to your account.

          This will open a web page where you can enter your details.
          """,
          flags: [
            help: [
              long: "--help",
              help: "Print usage docs",
              required: false
            ],
          ],
        ],
        logout: [
          name: "logout",
          about: "Log out of your account."
        ],
        signup: [
          name: "signup",
          about: """
          Sign up for an account.

          This will open a web page where you can enter your details.
          """
        ],
        whoami: [
          name: "whoami",
          about: "Display the logged-in user."
        ],
      ]
    ]
  end

  def login(_cmd) do
    throw :NotImplemented
  end

  def logout(_cmd) do
    throw :NotImplemented
  end

  def signup(_cmd) do
    throw :NotImplemented
  end

  def whoami(_cmd) do
    IO.inspect("No idea mate. Maybe go look in the mirror?")
  end
end
