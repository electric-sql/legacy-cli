defmodule Electric.Migrations.Sync do
  @moduledoc """

  """

  alias Electric.Client

  def sync_migrations(db_id, local_bundle) do
    with {:ok, server_manifest} <- get_migrations_from_server(db_id),
         {:ok, new_migrations} <- compare_local_with_server(local_bundle, server_manifest) do
      upload_new_migrations(db_id, new_migrations)
    end
  end

  def get_migrations_from_server(db_id) do
    url = "databases/#{db_id}/migrations"

    case Client.get(url) do
      {:ok, %Req.Response{status: 200, body: data}} ->
        {:ok, Jason.decode!(data)}

      {:ok, _} ->
        {:error, "invalid credentials"}

      {:error, _exception} ->
        {:error, "failed to connect"}
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
    Enum.reduce_while(server_migration_lookup, {:ok, "all here"}, fn {migration_name,
                                                                      server_migration},
                                                                     status ->
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
    end)
  end

  defp migration_lookup(bundle) do
    for migration <- bundle["migrations"], into: %{}, do: {migration["name"], migration}
  end

  def upload_new_migrations(db_id, new_migrations) do
    url = "databases/#{db_id}/migrations"
    payload = Jason.encode!(%{"migrations" => new_migrations}) |> Jason.Formatter.pretty_print()

    case Client.put(url, payload) do
      {:ok, %Req.Response{status: 200}} ->
        {:ok, "Synchronized #{length(new_migrations["migrations"])} new migrations successfully"}

      {:ok, _} ->
        {:error, "invalid credentials"}

      {:error, _exception} ->
        {:error, "failed to connect"}
    end
  end
end
