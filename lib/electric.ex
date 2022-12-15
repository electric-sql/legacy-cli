defmodule Electric do
  @moduledoc """
  Documentation for `Electric`.
  """
  use Bakeware.Script

  require Logger

  alias Electric.Commands
  alias Electric.Util

  @commands [
    accounts: Commands.Accounts,
    apps: Commands.Apps,
    auth: Commands.Auth,
    init: Commands.Config.Init,
    config: Commands.Config,
    migrations: Commands.Migrations
  ]

  @project Mix.Project.config()

  defp spec do
    subspecs =
      @commands
      |> Enum.map(fn {k, v} -> {k, v.spec()} end)

    Optimus.new!(
      name: "electric",
      description: "Electric SQL CLI",
      version: @project[:version],
      about: "...",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: subspecs
    )
  end

  @impl Bakeware.Script
  def main(argv \\ []) do
    case run(argv) do
      :ok ->
        :ok

      {:ok, output} when is_binary(output) ->
        IO.puts(output)

      {:error, output} ->
        IO.puts(output)
        System.halt(1)

      {:halt, status} ->
        System.halt(status)
    end
  end

  # allows for running the command without handling the result and causing the system to exit
  @doc false
  def run(argv \\ []) do
    argv
    |> parse()
    |> set_verbosity()
    |> route()
    |> map_result()
  end

  def parse(argv \\ []) do
    Optimus.parse!(spec(), argv, &halt/1)
  end

  defp route({command_path, %{flags: %{help: true}}}) when is_list(command_path) do
    Optimus.parse!(spec(), ["help" | Enum.map(command_path, &to_string/1)], &halt/1)
  end

  defp route({[key, command], options}) when is_atom(key) and is_atom(command) do
    @commands
    |> Keyword.get(key)
    |> apply(command, [options])
  end

  # not liking the constant impedence mismatch between the cli and optimus
  defp route({[:init], options}) do
    apply(Commands.Config, :init, [options])
  end

  defp route({[key], _}) do
    spec()
    |> Optimus.parse!(["help", "#{key}"], &halt/1)
  end

  defp route(_) do
    spec()
    |> Optimus.parse!(["--help"], &halt/1)
  end

  defp map_result({:result, data}) when is_binary(data) do
    {:ok, data}
  end

  defp map_result({:result, data}) do
    {:ok, output} = Jason.encode(data, pretty: true)

    {:ok, output}
  end

  defp map_result({:results, data}) do
    {:ok, output} = Jason.encode(data, pretty: true)

    {:ok, output}
  end

  defp map_result({:success, message}) do
    output = Util.format_success(message)

    {:ok, output}
  end

  defp map_result({:help, subcommand, message}) when is_binary(message) do
    map_result({:help, subcommand, message, 1})
  end

  defp map_result({:help, subcommand, message, status}) when is_binary(message) do
    spec()
    |> Optimus.Errors.format(subcommand, [message])
    |> Enum.join("\n")
    |> String.trim_trailing()
    |> IO.write()

    spec()
    |> Optimus.parse!(["help" | Enum.map(subcommand, &to_string/1)], fn _ -> halt(status) end)
  end

  defp map_result({:error, error}) when is_binary(error) do
    map_result({:error, [error]})
  end

  defp map_result({:error, errors}) when is_list(errors) do
    output =
      spec()
      |> Optimus.Errors.format(errors)
      |> Enum.join("\n")

    {:error, output}
  end

  defp map_result({:halt, 0}) do
    {:halt, 0}
  end

  defp halt(status) do
    {:halt, status}
  end

  defp set_verbosity({_route, %{flags: flags}} = options) do
    Electric.Util.enable_verbose(Map.get(flags, :verbose, false))

    options
  end

  defp set_verbosity(options) do
    options
  end

  @doc """
  Provide `use Electric, :command`.
  """
  defmacro __using__(:command) do
    Electric.Commands.command()
  end
end
