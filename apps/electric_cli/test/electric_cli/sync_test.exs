defmodule ElectricCli.ElectricCli.SyncTest do
  use ElectricCli.CommandCase, async: false

  alias ElectricCli.Config.Environment

  alias ElectricCli.Manifest
  alias ElectricCli.Manifest.Migration

  alias ElectricCli.Migrations.Api
  alias ElectricCli.Migrations.Sync

  describe "sync tests" do
    setup :login

    test "gets an empty set of migrations" do
      assert {:ok, %Manifest{migrations: []}} =
               Api.get_server_migrations("app-name", "production")
    end

    test "uploads new migrations" do
      migrations = [
        %{
          "name" => "migration_name",
          "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
          "encoding" => "escaped",
          "original_body" =>
            "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
          "satellite_body" => [
            "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
            "--ADD A TRIGGER FOR main.items;"
          ],
          "title" => "migration name"
        }
        |> Migration.new(),
        %{
          "name" => "migration_name_2",
          "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3",
          "encoding" => "escaped",
          "original_body" =>
            "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
          "satellite_body" => [
            "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
            "--ADD A TRIGGER FOR main.cat;",
            "--ADD A TRIGGER FOR main.items;"
          ],
          "title" => "migration name 2"
        }
        |> Migration.new()
      ]

      {:ok, msg} = Sync.upload_new_migrations("app-name", "production", migrations)

      assert msg =~ "Synced 2 new migrations"
    end

    test "handles 422 error responses for invalid migrations" do
      migrations = [
        %{
          "name" => "migration_name",
          "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
          "encoding" => "escaped",
          "original_body" =>
            "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
          "satellite_body" => [
            "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
            "--ADD A TRIGGER FOR main.items;"
          ],
          "title" => "migration name"
        }
        |> Migration.new()
      ]

      # Using app = "status-422" triggers hard-coded error response
      {:error, ["The table items is not STRICT."]} =
        Sync.upload_new_migrations("status-422", "production", migrations)
    end

    test "compare local to server bundles" do
      local_manifest =
        Manifest.new(%{
          app: "a",
          migrations: [
            %{
              "name" => "1666612306_test_migration",
              "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration"
            },
            %{
              "name" => "1666612307_test_migration_2",
              "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.cat;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration 2"
            }
          ]
        })

      server_manifest =
        Manifest.new(%{
          app: "a",
          migrations: []
        })

      assert {:ok, new_migrations} =
               Sync.compare_local_with_server(local_manifest, server_manifest)

      assert new_migrations == local_manifest.migrations
    end

    test "excludes existing migrations" do
      local_manifest =
        Manifest.new(%{
          app: "a",
          migrations: [
            %{
              "name" => "1666612306_test_migration",
              "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration"
            },
            %{
              "name" => "1666612307_test_migration_2",
              "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.cat;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration 2"
            }
          ]
        })

      server_manifest =
        Manifest.new(%{
          app: "a",
          migrations: [
            %{
              "name" => "1666612306_test_migration",
              "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
              "title" => "test migration"
            }
          ]
        })

      expected =
        %{
          "name" => "1666612307_test_migration_2",
          "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3",
          "encoding" => "escaped",
          "original_body" =>
            "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
          "satellite_body" => [
            "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
            "--ADD A TRIGGER FOR main.cat;",
            "--ADD A TRIGGER FOR main.items;"
          ],
          "title" => "test migration 2"
        }
        |> Migration.new()

      assert {:ok, [^expected]} = Sync.compare_local_with_server(local_manifest, server_manifest)
    end

    test "fails if migration altered" do
      local_manifest =
        Manifest.new(%{
          app: "a",
          migrations: [
            %{
              "name" => "1666612306_test_migration",
              "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration"
            },
            %{
              "name" => "1666612307_test_migration_2",
              "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.cat;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration 2"
            }
          ]
        })

      server_manifest =
        Manifest.new(%{
          app: "a",
          migrations: [
            %{
              "name" => "1666612306_test_migration",
              "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76774",
              "title" => "test migration"
            }
          ]
        })

      assert {:error, msg} = Sync.compare_local_with_server(local_manifest, server_manifest)
      assert msg == "The migration 1666612306_test_migration has been changed locally"
    end

    test "fails if migration missing" do
      local_manifest =
        Manifest.new(%{
          app: "a",
          migrations: [
            %{
              "name" => "1666612307_test_migration_2",
              "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.cat;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration 2"
            }
          ]
        })

      server_manifest =
        Manifest.new(%{
          app: "a",
          migrations: [
            %{
              "name" => "1666612306_test_migration",
              "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
              "title" => "test migration"
            }
          ]
        })

      assert {:error, msg} = Sync.compare_local_with_server(local_manifest, server_manifest)
      assert msg == "The migration 1666612306_test_migration is missing locally"
    end

    test "doing whole sync" do
      local_manifest =
        Manifest.new(%{
          app: "app-name-2",
          migrations: [
            %{
              "name" => "1666612306_test_migration",
              "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration"
            },
            %{
              "name" => "1666612307_test_migration_2",
              "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3",
              "encoding" => "escaped",
              "original_body" =>
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "satellite_body" => [
                "CREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
                "--ADD A TRIGGER FOR main.cat;",
                "--ADD A TRIGGER FOR main.items;"
              ],
              "title" => "test migration 2"
            }
          ]
        })

      target_environment = Environment.new(%{slug: "production"})

      assert {:ok, msg} = Sync.sync_migrations(local_manifest, target_environment)
      assert msg =~ "Synced 1 new migration"
    end
  end
end
