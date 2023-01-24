import Config

default_console_url =
  case config_env() do
    :prod -> "https://console.electric-sql.com"
    :test -> "http://localhost:4005"
    :dev -> "http://localhost:4000"
  end

config :electric_cli,
  default_console_url: default_console_url,
  default_env: "default",
  default_migrations_dir: "migrations",
  default_output_dir: ".electric",
  config_filename: "electric.json",
  verbose: false

if config_env() == :dev do
  config :electric_cli,
    mode: :dev

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

if config_env() == :prod do
  config :electric_cli,
    mode: :prod

  config :logger, level: :emergency
end

if config_env() == :test do
  config :electric_cli,
    mode: :test
end
