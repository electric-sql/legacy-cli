defmodule ElectricCli.Commands.Apps do
  @moduledoc """
  The `Apps` command.
  """
  use ElectricCli, :command

  @app [
    app: [
      value_name: "APP",
      help: "App ID (e.g.: from `electric apps list`)",
      required: true,
      parser: :string
    ]
  ]

  def spec do
    [
      name: "apps",
      about: "Manage backend applications.",
      subcommands: [
        # create: [
        #   name: "create",
        #   about: """
        #   Create a new application.

        #   Create a new application and provision the associated
        #   database infrastructure and replication systems.
        #   """,
        #   flags: default_flags()
        # ],
        # destroy: [
        #   name: "destroy",
        #   about: """
        #   Permanently destroy an application.

        #   Delete an application and permanently destroy the associated
        #   data, database infrastructure and replication systems.
        #   """,
        #   flags: default_flags()
        # ],
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
          args: @app,
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
    with :ok <- Session.require_auth() do
      result =
        Progress.run("Listing apps", false, fn ->
          Client.get("apps")
        end)

      case result do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
          rows =
            Enum.flat_map(
              data,
              &Enum.map(&1["databases"], fn db ->
                [
                  &1["id"],
                  &1["name"],
                  db["slug"],
                  colorize_status(db["status"]) |> IO.iodata_to_binary()
                ]
              end)
            )

          {:results, rows, ["ID", "Name", "Environment", "Status"]}

        {:ok, %Req.Response{}} ->
          {:error, "invalid credentials"}

        {:error, _exception} ->
          {:error, "couldn't connect to ElectricSQL servers"}
      end
    end
  end

  defp colorize_status("provisioned" = text), do: [IO.ANSI.green(), text, IO.ANSI.reset()]

  defp colorize_status("provisioning" = text),
    do: [IO.ANSI.yellow(), IO.ANSI.blink_slow(), text, IO.ANSI.reset()]

  defp colorize_status("migrating" = text),
    do: [IO.ANSI.yellow(), IO.ANSI.blink_slow(), text, IO.ANSI.reset()]

  defp colorize_status("failed" = text), do: [IO.ANSI.red(), text, IO.ANSI.reset()]

  # # flags: %{}, options: %{}, unknown: []}
  # def open(_cmd) do
  #   throw(:NotImplemented)
  # end

  def show(%{args: %{app: app}}) do
    with :ok <- Session.require_auth() do
      path = "apps/#{app}"

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
          {:error, "couldn't connect to ElectricSQL servers"}
      end
    end
  end
end
