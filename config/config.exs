import Config

if config_env() == :dev do
  config :electric_sql_cli,
    base_url: "http://localhost:4000/api/v1/"

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
