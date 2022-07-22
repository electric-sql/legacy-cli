Code.put_compiler_option(:ignore_module_conflict, true)

defmodule Electric.MixProject do
  use Mix.Project

  def project do
    [
      app: :electric,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Electric.Main, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:optimus, [git: "git@github.com:thruflo/optimus.git"]},
      {:bakeware, "~> 0.2.4", runtime: false}
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
