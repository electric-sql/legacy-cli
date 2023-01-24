defmodule ElectricCli.Migrations.Sync do
  @moduledoc """
  Sync migrations up-to and down-from the server.
  """

  alias ElectricCli.Config.Environment
  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration
  alias ElectricCli.Migrations.Api

  def sync_migrations(%Manifest{app: app} = local_manifest, %Environment{slug: env}) do
    with {:ok, %Manifest{} = server_manifest} <- Api.get_server_migrations(app, env),
         {:ok, new_migrations} <- compare_local_with_server(local_manifest, server_manifest),
         {:ok, msg} <- upload_new_migrations(app, env, new_migrations),
         :ok <- apply_all_migrations(app, env) do
      {:ok, msg}
    end
  end

  def apply_all_migrations(app, env) do
    with {:ok, %Manifest{migrations: migrations}} <- Api.get_server_migrations(app, env) do
      migrations
      |> List.last()
      |> Api.apply_migration(app, env)
    end
  end

  def compare_local_with_server(
        %Manifest{migrations: local_migrations},
        %Manifest{migrations: server_migrations}
      ) do
    local_migration_map =
      local_migrations
      |> Enum.map(fn %Migration{name: name, sha256: sha256} -> {name, sha256} end)
      |> Enum.into(%{})

    server_migration_names =
      server_migrations
      |> Enum.map(fn %Migration{name: name} -> name end)

    with :ok <- has_all_server_migrations_locally(server_migrations, local_migration_map) do
      new_migrations =
        local_migrations
        |> Enum.reject(&is_existing_migration(&1, server_migration_names))

      {:ok, new_migrations}
    end
  end

  defp has_all_server_migrations_locally(migrations, migration_map) do
    migrations
    |> Enum.reduce_while(:ok, fn %Migration{name: name, sha256: sha256}, :ok ->
      case migration_map[name] do
        ^sha256 ->
          {:cont, :ok}

        nil ->
          {:halt, {:error, "The migration #{name} is missing locally"}}

        _alt ->
          {:halt, {:error, "The migration #{name} has been changed locally"}}
      end
    end)
  end

  defp is_existing_migration(%Migration{name: name}, existing_migration_names) do
    existing_migration_names
    |> Enum.member?(name)
  end

  def upload_new_migrations(app, env, migrations) do
    success_message =
      case Enum.count(migrations) do
        0 -> "No new migrations to sync"
        1 -> "Synced 1 new migration"
        n -> "Synced #{n} new migrations"
      end

    migrations
    |> Enum.reduce_while({:ok, success_message}, fn %Migration{} = migration, status ->
      case Api.upload_new_migration(app, env, migration) do
        {:ok, _msg} ->
          {:cont, status}

        {:error, msg} ->
          {:halt, {:error, msg}}
      end
    end)
  end
end
