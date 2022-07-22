defmodule Electric.Main do
  @moduledoc """
  Documentation for `Electric`.
  """
  use Bakeware.Script

  require Logger

  alias Electric.Contexts

  @contexts [
    accounts: Contexts.Accounts,
    auth: Contexts.Auth
  ]

  @project Mix.Project.config

  defp spec do
    subspecs =
      @contexts
      |> Enum.map(fn {k, v} -> {k, v.spec()} end)

    Optimus.new!(
      name: "#{@project[:app]}",
      description: "Electric SQL CLI",
      version: @project[:version],
      about: "...",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: subspecs
    )
  end

  @impl Bakeware.Script
  def main(argv) do
    argv
    |> parse()
    |> route()

    0
  end

  defp parse(argv) do
    spec()
    |> Optimus.parse!(argv)
  end

  defp route({[key, command], %{flags: %{help: true}}}) do
    spec()
    |> Optimus.parse!(["help", "#{key}", "#{command}"])
  end

  defp route({[key, command], options}) when is_atom(key) and is_atom(command) do
    @contexts
    |> Keyword.get(key)
    |> apply(command, [options])
  end

  defp route({[key], _}) do
    spec()
    |> Optimus.parse!(["help", "#{key}"])
  end

  defp route(_) do
    spec()
    |> Optimus.parse!(["--help"])
  end
end
