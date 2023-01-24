defmodule ElectricCli.ConfigCommandHelpers do
  @moduledoc """
  Helper and fixture-like functions for the command tests.
  """
  import ExUnit.Assertions, only: [assert: 1]

  alias ElectricCli.Config
  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration

  def assert_config(root, %{
        app: expected_app,
        env: expected_env,
        migrations_dir: expected_migrations_dir
      }) do
    assert {:ok, %Config{app: app, defaultEnv: env, directories: directories}} = Config.load(root)

    assert ^expected_app = app
    assert ^expected_env = env

    relative_migrations_dir =
      directories
      |> Config.contract_directories(root)
      |> Map.get(:migrations)

    migrations_dir =
      relative_migrations_dir
      |> Path.expand(root)

    assert ^expected_migrations_dir = relative_migrations_dir
    assert File.dir?(migrations_dir)

    migrations =
      migrations_dir
      |> Path.join("*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    assert true =
             migrations_dir
             |> Path.join("manifest.json")
             |> File.exists?()

    # Match on a length-1 array to assert that only one init migration
    # has been created.
    assert [init_migration] = Enum.filter(migrations, &is_init_migration/1)

    assert true =
             init_migration
             |> Path.join("migration.sql")
             |> File.exists?()

    assert {:ok, %Manifest{migrations: [%Migration{}]}} =
             Manifest.load(app, migrations_dir, false)
  end

  defp is_init_migration(path) do
    Path.basename(path) =~ ~r/^[\d_]+_init/
  end
end
