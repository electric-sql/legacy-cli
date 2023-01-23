defmodule ElectricCli.Migrations.Sync do
  @moduledoc """

  """

  alias ElectricCli.Client

  def sync_migrations(app, env, local_bundle) do
    with {:ok, server_manifest} <- get_migrations_from_server(app, env),
         {:ok, new_migrations} <- compare_local_with_server(local_bundle, server_manifest),
         {:ok, msg} <- upload_new_migrations(app, env, new_migrations),
         {:ok, _} <- apply_all_migrations(app, env) do
      {:ok, msg}
    end
  end

  def apply_all_migrations(app, env) do
    with {:ok, manifest} <- get_migrations_from_server(app, env) do
      last_migration = List.last(manifest["migrations"])

      if last_migration["status"] == "not_applied" do
        url = "apps/#{app}/environments/#{env}/migrate"

        case Client.post(url, %{"migration_name" => last_migration["name"]}) do
          {:ok, %Req.Response{status: 200, body: _body}} ->
            {:ok, nil}

          {:ok, %Req.Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
            {:error, msg}

          {:ok, %Req.Response{body: %{"errors" => %{"detail" => msg}}}} ->
            {:error, msg}

          {:ok, %Req.Response{body: %{"error" => %{"message" => msg}}}} ->
            {:error, msg}

          {:error, _exception} ->
            {:error, "couldn't connect to ElectricSQL servers"}
        end
      else
        {:ok, nil}
      end
    end
  end

  def get_migrations_from_server(app, env, with_satellite \\ false) do
    url =
      if with_satellite do
        "apps/#{app}/environments/#{env}/migrations?body=satellite"
      else
        "apps/#{app}/environments/#{env}/migrations"
      end

    case Client.get(url) do
      {:ok, %Req.Response{status: 200, body: data}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 404, body: _data}} ->
        {:error, "app '#{app}' with env '#{env}' not found. Was it deleted?",
         [
           "Check ",
           IO.ANSI.yellow(),
           "electric apps list",
           IO.ANSI.reset(),
           " for available apps."
         ]}

      {:ok, %Req.Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Req.Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  def get_full_migration_from_server(app, env, migration_name) do
    url = "apps/#{app}/environments/#{env}/migrations/#{migration_name}?body=all"

    case Client.get(url) do
      {:ok, %Req.Response{status: 200, body: data}} ->
        {:ok, data}

      {:ok, %Req.Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Req.Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  def get_all_migrations_from_server(app) do
    with {:ok, env_names} <- get_env_names_from_server(app) do
      Enum.reduce_while(env_names, {:ok, %{}}, fn env_name, {_status, manifests} ->
        case get_migrations_from_server(app, env_name) do
          {:error, msg} ->
            {:halt, {:error, msg}}

          {:ok, manifest} ->
            {:cont, {:ok, Map.put(manifests, env_name, manifest)}}
        end
      end)
    end
  end

  def get_env_names_from_server(app) do
    url = "apps/#{app}"

    case Client.get(url) do
      {:ok, %Req.Response{status: 200, body: data}} ->
        as_json = data

        names =
          for database <- as_json["data"]["databases"] do
            database["slug"]
          end

        {:ok, names}

      {:ok, %Req.Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Req.Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  def compare_local_with_server(local_bundle, server_manifest) do
    local_migration_lookup = migration_lookup(local_bundle)
    server_migration_lookup = migration_lookup(server_manifest)
    server_migration_names = Map.keys(server_migration_lookup)

    with {:ok, _msg} <-
           has_all_server_migrations_locally(local_migration_lookup, server_migration_lookup) do
      new_migrations =
        for local_migration <- local_bundle["migrations"],
            local_migration["name"] not in server_migration_names do
          local_migration
        end

      {:ok, %{"migrations" => new_migrations}}
    end
  end

  defp has_all_server_migrations_locally(local_migration_lookup, server_migration_lookup) do
    Enum.reduce_while(
      server_migration_lookup,
      {:ok, "all here"},
      fn {migration_name, server_migration}, status ->
        case local_migration_lookup[migration_name] do
          nil ->
            {:halt, {:error, "The migration #{migration_name} is missing locally"}}

          migration ->
            if migration["sha256"] == server_migration["sha256"] do
              {:cont, status}
            else
              {:halt, {:error, "The migration #{migration_name} has been changed locally"}}
            end
        end
      end
    )
  end

  defp migration_lookup(bundle) do
    for migration <- bundle["migrations"], into: %{}, do: {migration["name"], migration}
  end

  def upload_new_migrations(app, env, new_migrations) do
    migrations = new_migrations["migrations"]

    Enum.reduce_while(
      migrations,
      {:ok, "Synchronized #{length(migrations)} new migrations successfully"},
      fn migration, status ->
        case upload_new_migration(app, env, migration) do
          {:ok, _msg} ->
            {:cont, status}

          {:error, msg} ->
            {:halt, {:error, msg}}
        end
      end
    )
  end

  def upload_new_migration(app, env, migration) do
    url = "apps/#{app}/environments/#{env}/migrations"

    case Client.post(url, %{"migration" => migration}) do
      {:ok, %Req.Response{status: 201}} ->
        {:ok, "ok"}

      {:ok, %Req.Response{body: %{"errors" => %{"detail" => [msg]}}}} ->
        {:error, msg}

      {:ok, %Req.Response{body: %{"errors" => %{"original_body" => [_ | _] = msgs}}}} ->
        {:error, msgs}

      {:ok, %Req.Response{body: %{"error" => %{"message" => msg}}}} ->
        {:error, msg}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end
end
