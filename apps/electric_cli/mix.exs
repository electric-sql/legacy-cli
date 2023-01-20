Code.put_compiler_option(:ignore_module_conflict, true)

defmodule ElectricCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :electric_cli,
      version: "0.3.0",
      elixir: "~> 1.14",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    Mix.env()
    |> application()
  end

  defp application(:test) do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  defp application(_) do
    [
      extra_applications: [:logger, :eex],
      mod: {ElectricCli.Main, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/mocks", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bakeware, "~> 0.2.4", runtime: false},
      {:cli_spinners, [github: "thruflo/elixir_cli_spinners"]},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:exconstructor, "~> 1.2.6"},
      {:git_hooks, "== 0.6.5", only: :dev, runtime: false},
      {:jason, "~> 1.3.0"},
      {:memoize, "~> 1.4"},
      {:optimus, [github: "icehaunter/optimus"]},
      {:table_rex, "~> 3.1"},
      {:req, "~> 0.3.0"},
      {:exqlite, "~> 0.11.3"},
      {:uuid, "~> 1.1.8"},
      {:plug_cowboy, "~> 2.0", only: :test},
      {:electric_migrations, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      dev: "run dev.exs"
    ]
  end

  def releases do
    [
      electric: [
        bakeware: [
          compression_level: compression(Mix.env()),
          start_command: "start"
        ],
        overwrite: true,
        quiet: true,
        steps: [
          :assemble,
          &Bakeware.assemble/1
        ],
        strip_beams: Mix.env() == :prod
      ]
    ]
  end

  defp compression(:prod), do: 19
  defp compression(_), do: 1
end
