defmodule ElectricCli.Commands.CommandFixtures do
  @moduledoc """
  Helper and fixture-like functions for the command tests.
  """
  import ElectricCli.Commands.CommandHelpers, only: [run_cmd: 1]

  @default_email "test@electric-sql.com"
  @default_password "password"

  @default_app "tarragon-envy-1337"
  @additional_env "staging"

  def init(%{} = ctx) when not is_map_key(ctx, :app) do
    ctx
    |> Map.put(:app, @default_app)
    |> init()
  end

  def init(%{app: app} = ctx) do
    {{:ok, _}, _} = run_cmd("init #{app}")

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
end
