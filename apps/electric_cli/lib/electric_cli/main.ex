defmodule ElectricCli.Main do
  use Bakeware.Script

  require Logger

  alias ElectricCli.Output.Formatting
  alias ElectricCli.Commands
  alias ElectricCli.Util

  @commands [
    accounts: Commands.Accounts,
    apps: Commands.Apps,
    auth: Commands.Auth,
    build: Commands.Build,
    config: Commands.Config,
    init: Commands.Init,
    migrations: Commands.Migrations,
    reset: Commands.Reset,
    sync: Commands.Sync
  ]

  @top_level_commands [
    :build,
    :init,
    :reset,
    :sync
  ]

  @project Mix.Project.config()

  @spec spec :: any()
  def spec do
    subspecs =
      @commands
      |> Enum.map(fn {k, v} -> {k, v.spec()} end)

    Optimus.new!(
      name: "electric",
      description: "ElectricSQL CLI",
      version: @project[:version],
      about: "Command line interface to the https://electric-sql.com service.",
      allow_unknown_args: false,
      parse_double_dash: true,
      flags: [
        verbose: [
          long: "--verbose",
          short: "-v",
          help: "Output more information about the CLI actions.",
          required: false,
          global: true
        ]
      ],
      subcommands: subspecs
    )
  end

  @doc """
  Run the command, print the output and exit.
  """
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

  @doc """
  Run the command and return the result (without exiting).
  """
  def run(argv \\ []) do
    argv
    |> prepend_help_flag()
    |> parse()
    |> case do
      :version ->
        spec()
        |> Optimus.Title.title()
        |> join_lines()

      :help ->
        spec()
        |> Optimus.Help.help([], columns())
        |> join_lines()

      {:help, subcommand} ->
        spec()
        |> Optimus.Help.help(subcommand, columns())
        |> join_lines()

      {:error, errors} ->
        formatted_errors =
          spec()
          |> Formatting.format_errors(errors)
          |> Enum.join("\n")

        {:error, formatted_errors}

      {:error, subcommand, errors} ->
        formatted_errors =
          spec()
          |> Formatting.format_errors(subcommand, errors)
          |> Enum.join("\n")

        {:error, formatted_errors}

      ok_tuple ->
        ok_tuple
        |> get_subcommand_and_result()
        |> set_verbosity()
        |> execute()
        |> map_result()
    end
  end

  defp prepend_help_flag(["--help"] = args), do: args

  defp prepend_help_flag(args) do
    case Enum.group_by(args, &(&1 == "--help")) do
      %{true: _, false: ["help" | _] = other_args} -> other_args
      %{true: _} = map -> ["help" | Map.get(map, false, [])]
      _ -> args
    end
  end

  defp get_subcommand_and_result({:ok, subcommand, result}), do: {subcommand, result}
  defp get_subcommand_and_result({:ok, result}), do: {[], result}

  def parse(argv \\ []) do
    Optimus.parse(spec(), argv)
  end

  defp execute({[], _}), do: Optimus.parse!(spec(), ["--help"], &halt/1)
  defp execute({[key, command], options}), do: apply(@commands[key], command, [options])

  defp execute({[key], options}) when key in @top_level_commands do
    @commands[key]
    |> apply(key, [options])
  end

  defp execute({[key], _options}), do: Optimus.parse!(spec(), ["help", "#{key}"], &halt/1)

  defp map_result({:result, data}) when is_binary(data) do
    {:ok, data}
  end

  defp map_result({:result, data}) do
    {:ok, output} = Jason.encode(data, pretty: true)

    {:ok, output}
  end

  defp map_result({:results, data, headers}) do
    {:ok,
     TableRex.Table.new(data, headers)
     |> TableRex.Table.render!(horizontal_style: :header, vertical_style: :off)}
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
    |> ElectricCli.Output.Formatting.format_errors(subcommand, [message])
    |> Enum.join("\n")
    |> String.trim_trailing()
    |> IO.puts()

    halt(status)
  end

  defp map_result({:error, errors}),
    do:
      {:error,
       ElectricCli.Output.Formatting.colorize_errors(List.wrap(errors)) |> Enum.join("\n")}

  defp map_result({:error, errors, hint}) do
    output =
      ElectricCli.Output.Formatting.colorize_errors(List.wrap(errors)) ++
        ["", hint]

    {:error, output |> Enum.join("\n")}
  end

  defp map_result({:halt, status}) do
    {:halt, status}
  end

  defp halt(status) do
    {:halt, status}
  end

  defp set_verbosity({_route, %{flags: flags}} = options) do
    ElectricCli.Util.enable_verbose(Map.get(flags, :verbose, false))

    options
  end

  defp set_verbosity(options) do
    options
  end

  defp join_lines(list) do
    {:ok, Enum.join(list, "\n")}
  end

  defp columns do
    case Optimus.Term.width() do
      {:ok, width} -> width
      _ -> 80
    end
  end
end
