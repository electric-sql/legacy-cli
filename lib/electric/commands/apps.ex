defmodule Electric.Commands.Apps do
  @moduledoc """
  The `Apps` command.
  """
  use Electric, :command

  def spec do
    [
      name: "apps",
      about: "Manage applications",
      subcommands: [
        create: [
          name: "create",
          about: """
          Create a new application.

          Create a new application and provision the associated
          database infrastructure and replication systems.
          """,
          flags: default_flags()
        ],
        destroy: [
          name: "destroy",
          about: """
          Permanently destroy an application.

          Delete an application and permanently destroy the associated
          data, database infrastructure and replication systems.
          """,
          flags: default_flags()
        ],
        list: [
          name: "list",
          about: """
          List your applications.

          List all your applications, grouped by account.
          """,
          flags: default_flags()
        ],
        open: [
          name: "open",
          about: """
          Open application in your browser.

          Open the management console web page for the application in
          your default browser.
          """,
          flags: default_flags()
        ]
        # resume
        # suspend
      ]
    ]
  end

  # flags: %{}, options: %{}, unknown: []}
  def create(_cmd) do
    throw(:NotImplemented)
  end

  # flags: %{}, options: %{}, unknown: []}
  def destroy(_cmd) do
    throw(:NotImplemented)
  end

  # flags: %{}, options: %{}, unknown: []}
  def list(_cmd) do
    throw(:NotImplemented)
  end

  # flags: %{}, options: %{}, unknown: []}
  def open(_cmd) do
    throw(:NotImplemented)
  end
end
