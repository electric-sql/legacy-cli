import Config
import System

base_url =
  if System.get_env("BASE_URL") != nil do
    System.get_env("BASE_URL")
  else
    "http://localhost:4000/api/v1/"
  end

if config_env() == :dev do
  config :electric_sql_cli,
    base_url: base_url

  # Git hooks for analysis and formatting.
  config :git_hooks,
    auto_install: true,
    hooks: [
      pre_commit: [
        tasks: [
          {:cmd, "mix format --check-formatted"}
        ]
      ],
      pre_push: [
        tasks: [
          # {:cmd, "mix dialyzer"},
          {:cmd, "mix test"}
        ]
      ]
    ]
end

if config_env() == :test do
  config :electric_sql_cli,
    base_url: "http://localhost:4003/api/v1/"
end
