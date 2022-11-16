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
   "test" =>  [
          %{
            "encoding" => "escaped",
            "name" => "first_migration_name",
            "satellite_body" => [
              "something random"],
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
     "test2" =>  [
          %{
            "encoding" => "escaped",
            "name" => "first_migration_name",
            "satellite_body" => [
              "something random"],
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

  defp get_some_migrations(app_name) do
    looked_up = @fixtures[app_name]
#    IO.inspect(looked_up)
    if looked_up == nil do
      []
    else
      looked_up
    end
  end

  get "api/v1/app/:app_name/env/:environment/migrations" do
    server_manifest = %{
      "migrations" => get_some_migrations(app_name)
    }

    Plug.Conn.resp(conn, 200, Jason.encode!(server_manifest))
    |> Plug.Conn.send_resp()
  end

  post "api/v1/app/:app_name/env/:environment/migrations" do

    Plug.Conn.resp(conn, 201, "ok")
    |> Plug.Conn.send_resp()
  end

  get "api/v1/app/:app_name/envs" do
    server_manifest = %{
      "environments" => ["default"]
    }

    Plug.Conn.resp(conn, 200, Jason.encode!(server_manifest))
    |> Plug.Conn.send_resp()
  end


end
