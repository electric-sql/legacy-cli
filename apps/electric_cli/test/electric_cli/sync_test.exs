defmodule ElectricCli.ElectricCli.SyncTest do
  use ExUnit.Case, async: false

  setup do
    start_link_supervised!(ElectricCli.MockServer.spec())

    :ok
  end

  test "gets an empty set of migrations" do
    {:ok, data} = ElectricCli.Migrations.Sync.get_migrations_from_server("app-name", "production")
    assert data == %{"migrations" => []}
  end

  test "uploads new migrations" do
    migrations = %{
      "migrations" => [
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
        },
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
      ]
    }

    {:ok, msg} =
      ElectricCli.Migrations.Sync.upload_new_migrations("app-name", "production", migrations)

    assert msg == "Synchronized 2 new migrations successfully"
  end

  test "handles 422 error responses for invalid migrations" do
    migrations = %{
      "migrations" => [
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
      ]
    }

    # Using app = "status-422" triggers hard-coded error response
    {:error, ["The table items is not STRICT."]} =
      ElectricCli.Migrations.Sync.upload_new_migrations("status-422", "production", migrations)
  end

  test "compare local to server bundles" do
    local_bundle = %{
      "migrations" => [
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
    }

    server_manifest = %{"migrations" => []}

    {:ok, new_migrations} =
      ElectricCli.Migrations.Sync.compare_local_with_server(local_bundle, server_manifest)

    assert new_migrations == local_bundle
  end

  test "excludes existing migrations" do
    local_bundle = %{
      "migrations" => [
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
    }

    server_manifest = %{
      "migrations" => [
        %{
          "name" => "1666612306_test_migration",
          "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
          "title" => "test migration"
        }
      ]
    }

    expected = %{
      "migrations" => [
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
    }

    {:ok, new_migrations} =
      ElectricCli.Migrations.Sync.compare_local_with_server(local_bundle, server_manifest)

    assert new_migrations == expected
  end

  test "fails if migration altered" do
    local_bundle = %{
      "migrations" => [
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
    }

    server_manifest = %{
      "migrations" => [
        %{
          "name" => "1666612306_test_migration",
          "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76774",
          "title" => "test migration"
        }
      ]
    }

    {:error, msg} =
      ElectricCli.Migrations.Sync.compare_local_with_server(local_bundle, server_manifest)

    assert msg == "The migration 1666612306_test_migration has been changed locally"
  end

  test "fails if migration missing" do
    local_bundle = %{
      "migrations" => [
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
    }

    server_manifest = %{
      "migrations" => [
        %{
          "name" => "1666612306_test_migration",
          "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
          "title" => "test migration"
        }
      ]
    }

    {:error, msg} =
      ElectricCli.Migrations.Sync.compare_local_with_server(local_bundle, server_manifest)

    assert msg == "The migration 1666612306_test_migration is missing locally"
  end

  test "doing whole sync" do
    local_bundle = %{
      "app" => "app-name-2",
      "migrations" => [
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
    }

    {:ok, msg} =
      ElectricCli.Migrations.Sync.sync_migrations("app-name-2", "production", local_bundle)

    assert msg == "Synchronized 1 new migrations successfully"
  end
end
