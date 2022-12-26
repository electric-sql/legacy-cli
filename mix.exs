Code.put_compiler_option(:ignore_module_conflict, true)

defmodule Electric.MixProject do
  use Mix.Project

  def project do
    [
      app: :electric_sql_cli,
      version: git_version(),
      elixir: "~> 1.13",
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

  defp application(:prod) do
    [
      extra_applications: [:logger, :eex],
      mod: {Electric, []}
    ]
  end

  defp application(_) do
    [
      extra_applications: [:logger, :eex]
    ]
  end

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
      {:plug_cowboy, "~> 2.0", only: :test}
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

  defp git_version() do
    {version, 0} =
      System.cmd("git", ~w"describe --dirty --abbrev=7 --tags --always --first-parent")

    version
    |> String.trim()
    |> String.replace_leading("v", "")
  end
end
