defmodule Electric.MockServer do
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["text/*"],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  @fixtures %{
    "app-name-2" => [
      %{
        "name" => "1666612306_test_migration",
        "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
        "title" => "test migration"
      }
    ],
    "test" => [
      %{
        "encoding" => "escaped",
        "name" => "first_migration_name",
        "satellite_body" => [
          "something random"
        ],
        "sha256" => "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
        "title" => "init"
      },
      %{
        "encoding" => "escaped",
        "name" => "second_migration_name",
        "satellite_body" => ["other stuff"],
        "sha256" => "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad6",
        "title" => "another"
      }
    ],
    "test2" => [
      %{
        "encoding" => "escaped",
        "name" => "first_migration_name",
        "satellite_body" => [
          "something random"
        ],
        "sha256" => "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
        "title" => "init"
      },
      %{
        "encoding" => "escaped",
        "name" => "second_migration_name",
        "satellite_body" => ["other stuff"],
        "sha256" => "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad7",
        "title" => "another"
      }
    ]
  }

  @migration_fixtures %{
    "second_migration_name" => %{
      "encoding" => "escaped",
      "name" => "second_migration_name",
      "satellite_body" => ["-- reverted satellite code"],
      "postgres_body" => "-- something",
      "original_body" => """
      /*
      Electric SQL Migration
      name: REVERTED VERSION OF THIS FILE
      title": another

      When you build or sync these migrations we will add some triggers and metadata
      so that Electric Satellite can sync your data.

      Write your SQLite migration below.
      */
      CREATE TABLE IF NOT EXISTS cats (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """,
      "sha256" => "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad7",
      "title" => "another"
    }
  }

  defp get_some_migrations(app_id) do
    looked_up = @fixtures[app_id]
    #    IO.inspect(looked_up)
    if looked_up == nil do
      []
    else
      looked_up
    end
  end

  defp get_a_migration(migration_name) do
    @migration_fixtures[migration_name]
  end

  get "api/v1/apps/:app_id/environment/:environment/migrations" do
    server_manifest = %{
      "migrations" => get_some_migrations(app_id)
    }

    Plug.Conn.resp(conn, 200, Jason.encode!(server_manifest))
    |> Plug.Conn.send_resp()
  end

  get "api/v1/apps/:app_id/environment/:environment/migrations/:migration_name" do
    server_manifest = %{
      "migration" => get_a_migration(migration_name)
    }

    Plug.Conn.resp(conn, 200, Jason.encode!(server_manifest))
    |> Plug.Conn.send_resp()
  end

  post "api/v1/apps/:app_id/environment/:environment/migrations" do
    Plug.Conn.resp(conn, 201, "ok")
    |> Plug.Conn.send_resp()
  end

  post "api/v1/apps/:app_id/environment/:environment/migrate" do
    Plug.Conn.resp(conn, 200, "ok")
    |> Plug.Conn.send_resp()
  end

  get "api/v1/apps/:app_id" do
    app_info = %{
      "databases" => [
        %{
          "slug" => "default"
        }
      ],
      "id" => "tame-cut-4121",
      "name" => "Example App",
      "slug" => "example-app"
    }

    Plug.Conn.resp(conn, 200, Jason.encode!(app_info))
    |> Plug.Conn.send_resp()
  end
end
