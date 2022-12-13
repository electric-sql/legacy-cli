import Config

default_base_url =
  case config_env() do
    :prod -> "https://console.electric-sql.com/api/v1/"
    :test -> "http://localhost:4003/api/v1/"
    :dev -> "http://localhost:4000/api/v1/"
  end

config :electric_sql_cli,
  default_base_url: default_base_url

if config_env() == :dev do
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
