defmodule Electric.Commands.Apps do
  @moduledoc """
  The `Apps` command.
  """
  use Electric, :command

  @app_id [
    app_id: [
      value_name: "APP_ID",
      help: "App ID (e.g.: from `electric apps list`)",
      required: true,
      parser: :string
    ]
  ]

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
        # open: [
        #   name: "open",
        #   about: """
        #   Open application in your browser.

        #   Open the management console web page for the application in
        #   your default browser.
        #   """,
        #   flags: default_flags()
        # ],
        show: [
          name: "show",
          about: """
          Show an application.

          Show informatiom about a specific application.
          """,
          args: @app_id,
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

  def list(_cmd) do
    result =
      Progress.run("Listing apps", false, fn ->
        Client.get("apps")
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

  # # flags: %{}, options: %{}, unknown: []}
  # def open(_cmd) do
  #   throw(:NotImplemented)
  # end

  def show(%{args: %{app_id: app_id}}) do
    path = "apps/#{app_id}"

    result =
      Progress.run("Getting app", false, fn ->
        Client.get(path)
      end)

    case result do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:result, data}

      {:ok, %Req.Response{}} ->
        {:error, "invalid credentials"}

      {:error, _exception} ->
        {:error, "failed to connect"}
    end
  end
end
