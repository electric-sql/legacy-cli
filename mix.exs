defmodule Cli.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end

  def releases do
    [
      electric: [
        applications: [cli: :permanent],
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
