defmodule ElectricCli.CommandFixtures do
  @moduledoc """
  Helper and fixture-like functions for the command tests.
  """
  import ElectricCli.CommandHelpers, only: [run_cmd: 1]

  @default_email "test@electric-sql.com"
  @default_password "password"

  @default_app "tarragon-envy-1337"
  @additional_env "staging"
  @default_migration_name "create foos"

  def init(%{} = ctx) when not is_map_key(ctx, :app) do
    ctx
    |> Map.put(:app, @default_app)
    |> init()
  end

  def init(%{app: app} = ctx) do
    {{:ok, _output}, _} = run_cmd("init #{app}")

    ctx
  end

  def init_no_verify(%{} = ctx) when not is_map_key(ctx, :app) do
    ctx
    |> Map.put(:app, @default_app)
    |> init_no_verify()
  end

  def init_no_verify(%{app: app} = ctx) do
    {{:ok, _output}, _} = run_cmd("init #{app} --no-verify")

    ctx
  end

  def add_env(%{} = ctx) when not is_map_key(ctx, :env) do
    ctx
    |> Map.put(:env, @additional_env)
    |> add_env()
  end

  def add_env(%{env: env} = ctx) do
    {{:ok, _}, _} = run_cmd("config add_env #{env}")

    ctx
  end

  def set_default_env(%{} = ctx) when not is_map_key(ctx, :default_env) do
    ctx
    |> Map.put(:default_env, @additional_env)
    |> set_default_env()
  end

  def set_default_env(%{default_env: default_env} = ctx) do
    {{:ok, _}, _} = run_cmd("config update_env #{default_env} --set-as-default")

    ctx
  end

  def login(%{} = ctx) when not is_map_key(ctx, :email) do
    ctx
    |> Map.put(:email, @default_email)
    |> login()
  end

  def login(%{} = ctx) when not is_map_key(ctx, :password) do
    ctx
    |> Map.put(:password, @default_password)
    |> login()
  end

  def login(%{email: email, password: password} = ctx) do
    {{:ok, _}, _} = run_cmd("auth login #{email} --password #{password}")

    ctx
  end

  def logout(%{} = ctx) do
    {{:ok, _}, _} = run_cmd("auth logout")

    ctx
  end

  def new_migration(%{} = ctx) when not is_map_key(ctx, :migration_name) do
    ctx
    |> Map.put(:migration_name, @default_migration_name)
    |> new_migration()
  end

  def new_migration(%{migration_name: migration_name} = ctx) do
    {{:ok, _}, _} = run_cmd(["migrations", "new", migration_name])

    ctx
  end

  def build(%{} = ctx) when not is_map_key(ctx, :env) do
    {{:ok, _}, _} = run_cmd("build")

    ctx
  end

  def build(%{env: env} = ctx) do
    {{:ok, _}, _} = run_cmd("build --env #{env}")

    ctx
  end

  def sync(%{} = ctx) when not is_map_key(ctx, :env) do
    {{:ok, _}, _} = run_cmd("sync")

    ctx
  end

  def sync(%{env: env} = ctx) do
    {{:ok, _}, _} = run_cmd("sync --env #{env}")

    ctx
  end
end
