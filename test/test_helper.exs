Code.require_file("mock_server.ex", "./test/mocks")

mock = [{Plug.Cowboy, scheme: :http, plug: Electric.MockServer, options: [port: 4003]}]
opts = [strategy: :one_for_one]
Supervisor.start_link(mock, opts)
ExUnit.start()
