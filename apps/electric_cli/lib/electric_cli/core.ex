defmodule ElectricCli.Core do
  @moduledoc """
  The context for the core `build`, `sync` and `reset commands.
  """
  alias ElectricCli.Bundle
  alias ElectricCli.Config
  alias ElectricCli.Config.Environment
  alias ElectricCli.Manifest
  alias ElectricCli.Migrations

  @doc """
  Update the manifest, write out postgres and satellite migrations
  files and bundle an importable js config module.
  """
  def build(
        %Config{app: app, directories: %{migrations: migrations_dir, output: output_dir}},
        %Environment{} = environment,
        has_postgres,
        has_satellite
      ) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, false),
         {:ok, %Manifest{} = manifest, warnings} <-
           Migrations.hydrate_manifest(manifest, migrations_dir, has_postgres, has_satellite),
         :ok <- Manifest.save(manifest, migrations_dir),
         :ok <- Migrations.optionally_write_postgres(manifest, migrations_dir, has_postgres),
         :ok <- Migrations.optionally_write_satellite(manifest, migrations_dir, has_satellite),
         :ok <- Bundle.write(manifest, environment, output_dir, "local"),
         {:warning, nil} <- {:warning, warnings} do
      :ok
    end
  end

  @doc """
  Sync migrations up-to and down-from the server and update the
  importable js config bundle to use the server migrations.
  """
  def sync(
        %Config{app: app, directories: %{migrations: migrations_dir, output: output_dir}},
        %Environment{slug: env} = environment
      ) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, false),
         {:ok, _msg} <- Migrations.Sync.sync_migrations(manifest, environment),
         {:ok, %Manifest{} = server_manifest} <-
           Migrations.Sync.get_migrations_from_server(manifest, environment, true) do
      server_manifest
      |> Bundle.write(environment, output_dir, env)
    end
  end

  @doc """
  Re-provision the backend database. Re-build the manifest and
  config bundle from the local files.
  """
  def reset(
        %Config{app: app, directories: %{migrations: migrations_dir, output: output_dir}},
        %Environment{slug: env} = environment
      ) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, false),
         :ok <- reset_backend(app, env) do
      manifest
      |> Bundle.write(environment, output_dir, "local")
    end
  end

  defp reset_backend(_app, _env) do
    # XXX use the client to hit the reset endpoint.
    # then poll the status until done.

    throw(:NotImplemented)
  end
end
