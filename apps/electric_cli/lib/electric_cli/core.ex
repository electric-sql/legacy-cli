defmodule ElectricCli.Core do
  @moduledoc """
  The context for the core `build`, `sync` and `reset commands.
  """
  alias ElectricCli.Bundle
  alias ElectricCli.Client
  alias ElectricCli.Config
  alias ElectricCli.Config.Environment
  alias ElectricCli.Manifest
  alias ElectricCli.Migrations
  alias ElectricCli.Migrations.Api
  alias ElectricCli.Migrations.Sync

  @doc """
  Update the manifest, write out postgres and satellite migrations
  files and bundle an importable js config module.
  """
  def build(
        %Config{
          app: app,
          debug: debug,
          directories: %{migrations: migrations_dir, output: output_dir}
        },
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
         :ok <- Bundle.write(manifest, environment, :local, debug, output_dir),
         {:warning, []} <- {:warning, warnings} do
      :ok
    end
  end

  @doc """
  Sync migrations up-to and down-from the server and update the
  importable js config bundle to use the server migrations.
  """
  def sync(
        %Config{
          app: app,
          debug: debug,
          directories: %{migrations: migrations_dir, output: output_dir}
        },
        %Environment{slug: env} = environment
      ) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, false),
         {:ok, %Manifest{} = manifest, []} <-
           Migrations.hydrate_manifest(manifest, migrations_dir),
         {:ok, dynamic_success_message} <- Sync.sync_migrations(manifest, environment),
         {:ok, %Manifest{} = server_manifest} <- Api.get_server_migrations(app, env, :satellite),
         :ok <- Bundle.write(server_manifest, environment, :server, debug, output_dir) do
      {:ok, dynamic_success_message}
    end
  end

  @doc """
  Re-provision the backend database. Re-build the manifest and
  config bundle from the local files.
  """
  def reset(
        %Config{
          app: app,
          debug: debug,
          directories: %{migrations: migrations_dir, output: output_dir}
        },
        %Environment{slug: env} = environment
      ) do
    with {:ok, %Manifest{} = manifest} <- Manifest.load(app, migrations_dir, false),
         :ok <- reset_backend(app, env) do
      manifest
      |> Bundle.write(environment, :local, debug, output_dir)
    end
  end

  # Use the client to hit the reset endpoint.
  # then poll the status until done.
  defp reset_backend(app, env) do
    path = "apps/#{app}/environments/#{env}/reset"

    with {:ok, %Req.Response{status: 200}} <- Client.post(path, %{}) do
      app
      |> poll_backend(env)
    else
      {:ok, %Req.Response{status: 400, body: %{"reason" => error_message}}} ->
        {:error, error_message}

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, :invalid_credentials}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end

  defp poll_backend(
         app,
         env,
         num_attempts \\ 1,
         delay_ms \\ 1_000,
         max_attempts \\ 50,
         max_delay_ms \\ 5_000,
         backoff_factor \\ 1.1
       ) do
    path = "apps/#{app}/environments/#{env}"

    with true <- num_attempts <= max_attempts,
         {:ok, %Req.Response{status: 200, body: %{"data" => %{"status" => status}}}} <-
           Client.get(path) do
      case status do
        val when val in ["provisioned", "migrating"] ->
          :ok

        "provisioning" ->
          :ok = Process.sleep(delay_ms)

          delay_ms =
            delay_ms
            |> increment_delay(max_delay_ms, backoff_factor)

          app
          |> poll_backend(env, delay_ms)

        "failed" ->
          {:error, "Provisioning failed", ["You may need to try again?"]}

        unknown_status ->
          {:error, "Unknown status: #{unknown_status}"}
      end
    else
      false ->
        {:error, "Provisioning timed out (exceeded #{max_attempts} retries)"}

      alt ->
        alt
    end
  end

  defp increment_delay(delay, max_delay, backoff_factor) do
    case round(delay * backoff_factor) do
      val when val <= max_delay ->
        val

      _alt ->
        max_delay
    end
  end
end
