defmodule Electric.MockServer do
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["text/*"],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  get "api/v1/app/1234/migrations" do
    data = %{"migrations" => []}

    Plug.Conn.resp(conn, 200, Jason.encode!(data))
    |> Plug.Conn.send_resp()
  end

  get "api/v1/app/5555/migrations" do
    server_manifest = %{
      "migrations" => [
        %{
          "name" => "1666612306_test_migration",
          "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775",
          "title" => "test migration"
        }
      ]
    }

    Plug.Conn.resp(conn, 200, Jason.encode!(server_manifest))
    |> Plug.Conn.send_resp()
  end

  put "api/v1/app/1234/migrations" do
    Plug.Conn.resp(conn, 200, "ok")
    |> Plug.Conn.send_resp()
  end

  put "api/v1/app/5555/migrations" do
    Plug.Conn.resp(conn, 200, "ok")
    |> Plug.Conn.send_resp()
  end
end
