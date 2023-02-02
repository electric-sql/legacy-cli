defmodule ElectricCli.MockServer do
  use Plug.Router
  alias Plug.Conn

  def spec do
    {Plug.Cowboy, scheme: :http, plug: ElectricCli.MockServer, options: [port: 4005]}
  end

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
        "title" => "test migration",
        "status" => "applied"
      }
    ],
    "test" => [
      %{
        "encoding" => "escaped",
        "name" => "first_migration_name",
        "status" => "applied",
        "satellite_body" => [
          "something random"
        ],
        "sha256" => "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
        "title" => "init"
      },
      %{
        "encoding" => "escaped",
        "name" => "second_migration_name",
        "status" => "applied",
        "satellite_body" => ["other stuff"],
        "sha256" => "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad6",
        "title" => "another"
      }
    ],
    "test2" => [
      %{
        "encoding" => "escaped",
        "name" => "first_migration_name",
        "status" => "applied",
        "satellite_body" => [
          "something random"
        ],
        "sha256" => "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
        "title" => "init"
      },
      %{
        "encoding" => "escaped",
        "name" => "second_migration_name",
        "original_body" => """
        /*
        ElectricSQL Migration
        name: REVERTED VERSION OF THIS FILE
        title": another

        When you build or sync these migrations we will add some triggers and metadata
        so that ElectricSQL's Satellite component can sync your data.

        Write your SQLite migration below.
        */
        CREATE TABLE IF NOT EXISTS cats (
          value TEXT PRIMARY KEY
        ) STRICT, WITHOUT ROWID;
        """,
        "status" => "applied",
        "satellite_body" => ["other stuff"],
        "sha256" => "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad7",
        "title" => "another"
      }
    ],
    "sync-from-1234" => [
      %{
        "encoding" => "escaped",
        "name" => "first_migration_name",
        "status" => "applied",
        "original_body" => "SELECT 1",
        "satellite_body" => ["something random"],
        "sha256" => "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
        "title" => "init"
      },
      %{
        "encoding" => "escaped",
        "name" => "second_migration_name",
        "original_body" => "SELECT 2",
        "status" => "applied",
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
      "status" => "applied",
      "satellite_body" => ["-- reverted satellite code"],
      "postgres_body" => "-- something",
      "original_body" => """
      /*
      ElectricSQL Migration
      name: REVERTED VERSION OF THIS FILE
      title": another

      When you build or sync these migrations we will add some triggers and metadata
      so that ElectricSQL's Satellite component can sync your data.

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

  defp get_migrations(app) do
    case @fixtures[app] do
      nil ->
        []

      alt ->
        alt
    end
  end

  defp get_migration(name) do
    @migration_fixtures[name]
  end

  defp authenticated(conn) do
    case Enum.find(conn.req_headers, fn {k, _v} -> k == "authorization" end) do
      {"authorization", "Bearer " <> _token} ->
        {:ok, conn}

      _alt ->
        data = %{
          error: %{
            details: "unauthenticated"
          }
        }

        conn
        |> json(401, data)
        |> Conn.send_resp()
    end
  end

  defp json(conn, status, data) when is_integer(status) do
    json_str = Jason.encode!(data)

    conn
    |> Conn.resp(status, json_str)
    |> Conn.put_resp_header("Content-Type", "application/json")
  end

  post "api/v1/auth/login" do
    case conn.body_params do
      %{"data" => %{"email" => "test@electric-sql.com", "password" => "password"}} ->
        data = %{
          email: "test@electric-sql.com",
          id: "00000000-0000-0000-0000-000000000000",
          token: "test_JWT_token",
          refreshToken: "test_refresh_JWT_token"
        }

        conn
        |> json(200, %{data: data})

      _ ->
        conn
        |> json(401, %{error: %{details: "no account with this email"}})
    end
  end

  get "api/v1/accounts" do
    with {:ok, conn} <- authenticated(conn) do
      accounts_list = %{
        data: [
          %{id: "277f2cae-98e2-11ed-aa13-1778becde5cf", name: "Personal", slug: "personal"},
          %{id: "2ef337c8-98e2-11ed-bd07-f378edb7fd12", name: "Work", slug: "work"}
        ]
      }

      conn
      |> json(200, accounts_list)
    end
  end

  get "api/v1/apps" do
    with {:ok, conn} <- authenticated(conn) do
      default_env = %{
        name: "Default",
        slug: "default",
        status: "provisioned",
        type: "postgres"
      }

      staging_env = %{
        name: "Staging",
        slug: "staging",
        status: "provisioned",
        type: "postgres"
      }

      apps_list = %{
        data: [
          %{id: "test", name: "test", slug: "test", databases: [default_env]},
          %{id: "test2", name: "test2", slug: "test2", databases: [default_env]},
          %{id: "app-name-2", name: "app-name-2", slug: "app-name-2", databases: [default_env]},
          %{
            id: "cranberry-soup-1337",
            name: "app-name-2",
            slug: "app-name-2",
            databases: [default_env, staging_env]
          },
          %{
            id: "french-onion-1234",
            name: "french-onion-1234",
            slug: "french-onion-1234",
            databases: [default_env]
          }
        ]
      }

      conn
      |> json(200, apps_list)
    end
  end

  get "api/v1/apps/:app" do
    with {:ok, conn} <- authenticated(conn) do
      app_info = %{
        "data" => %{
          "databases" => [
            %{
              "slug" => "default",
              "name" => "Default",
              "status" => "provisioned",
              "type" => "postgres"
            }
          ],
          "id" => app,
          "name" => "Example App",
          "slug" => "example-app"
        }
      }

      conn
      |> json(200, app_info)
    end
  end

  get "api/v1/apps/:app/environments/:env" do
    with {:ok, conn} <- authenticated(conn) do
      env_info = %{
        "data" => %{
          "slug" => "default",
          "name" => "Default",
          "status" => "provisioned",
          "type" => "postgres"
        }
      }

      conn
      |> json(200, env_info)
    end
  end

  get "api/v1/apps/:app/environments/:env/migrations" do
    with {:ok, conn} <- authenticated(conn) do
      data = %{
        "migrations" => get_migrations(app)
      }

      conn
      |> json(200, data)
    end
  end

  get "api/v1/apps/:app/environments/:env/migrations/:name" do
    with {:ok, conn} <- authenticated(conn) do
      data = %{
        "migration" => get_migration(name)
      }

      conn
      |> json(200, data)
    end
  end

  post "api/v1/apps/status-422/environments/:env/migrations" do
    with {:ok, conn} <- authenticated(conn) do
      data = %{
        errors: %{
          original_body: ["The table items is not STRICT."]
        }
      }

      conn
      |> json(422, data)
    end
  end

  post "api/v1/apps/:app/environments/:env/migrations" do
    with {:ok, conn} <- authenticated(conn) do
      conn
      |> json(201, "\"ok\"")
    end
  end

  post "api/v1/apps/:app/environments/:env/migrate" do
    with {:ok, conn} <- authenticated(conn) do
      conn
      |> json(200, "\"ok\"")
    end
  end

  post "api/v1/apps/:app/environments/:env/reset" do
    with {:ok, conn} <- authenticated(conn) do
      data = %{
        "detail" => "Database reset initiated."
      }

      conn
      |> json(200, data)
    end
  end
end
