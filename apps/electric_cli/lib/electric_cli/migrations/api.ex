defmodule ElectricCli.Migrations.Api do
  @moduledoc """
  Functions that call the migrations API.
  """
  alias Req.Response

  alias ElectricCli.Client
  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration

  def apply_migration(%Migration{name: name, status: "not_applied"}, app, env) do
    path = "apps/#{app}/environments/#{env}/migrate"

    data = %{
      "migration_name" => name
    }

    case Client.post(path, data) do
      {:ok, %Response{status: 200}} ->
        :ok

      {:ok, %Response{status: status}} when status in [401, 403] ->
        {:error, :invalid_credentials}

      {:ok, %Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Response{body: %{"errors" => %{"detail" => msg}}}} ->
        {:error, msg}

      {:ok, %Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  def apply_migration(%Migration{status: _other}, _, _), do: :ok
  def apply_migration(nil, _, _), do: :ok

  def get_full_server_migration(app, env, migration_name) do
    path = "apps/#{app}/environments/#{env}/migrations/#{migration_name}?body=all"

    case Client.get(path) do
      {:ok, %Response{status: 200, body: %{"migration" => data}}} ->
        {:ok, Migration.new(data)}

      {:ok, %Response{status: status}} when status in [401, 403] ->
        {:error, :invalid_credentials}

      {:ok, %Response{status: status}} when status in [404] ->
        {:error, :not_found}

      {:ok, %Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  def get_server_migrations(app, env, with_satellite \\ false) do
    path =
      if with_satellite do
        "apps/#{app}/environments/#{env}/migrations?body=satellite"
      else
        "apps/#{app}/environments/#{env}/migrations"
      end

    case Client.get(path) do
      {:ok, %Response{status: 200, body: %{"migrations" => migrations}}} ->
        {:ok, Manifest.new(%{app: app, migrations: migrations})}

      {:ok, %Response{status: 404, body: _data}} ->
        {:error, "app '#{app}' with env '#{env}' not found. Was it deleted?",
         [
           "Check ",
           IO.ANSI.yellow(),
           "electric apps list",
           IO.ANSI.reset(),
           " for available apps."
         ]}

      {:ok, %Response{status: status}} when status in [401, 403] ->
        {:error, :invalid_credentials}

      {:ok, %Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  def upload_new_migration(app, env, %Migration{} = migration) do
    path = "apps/#{app}/environments/#{env}/migrations"

    data = %{
      "migration" => Migration.upload_data(migration)
    }

    case Client.post(path, data) do
      {:ok, %Response{status: 201}} ->
        {:ok, "ok"}

      {:ok, %Response{status: status}} when status in [401, 403] ->
        {:error, :invalid_credentials}

      {:ok, %Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Response{body: %{"errors" => %{"original_body" => [_ | _] = msgs}}}} ->
        {:error, msgs}

      {:ok, %Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end
end
