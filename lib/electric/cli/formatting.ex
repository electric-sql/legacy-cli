defmodule Electric.Cli.Formatting do
  def format_error_without_usage(optimus, errors) do
    ["The following errors occurred:"] ++
      colorize_errors(errors) ++
      ["", "Try", "    #{optimus.name} --help", "", "to see available options", ""]
  end

  def format_errors(optimus, errors) do
    ["The following errors occurred:"] ++
      colorize_errors(errors) ++
      ["", "Try", "    #{optimus.name} --help", "", "to see available options", ""]
  end

  def format_errors(optimus, subcommand_path, errors) do
    {_subcommand, [_ | subcommand_name]} = Optimus.fetch_subcommand(optimus, subcommand_path)

    ["The following errors occurred:"] ++
      colorize_errors(errors) ++
      [
        "",
        "Usage: #{Optimus.Usage.usage(optimus, subcommand_path)}",
        "",
        "Try",
        "    #{optimus.name} help #{Enum.join(subcommand_name, " ")}",
        "",
        "to see available options",
        ""
      ]
  end

  def colorize_errors(errors) do
    Enum.map(
      errors,
      &[
        IO.ANSI.red(),
        IO.ANSI.bright(),
        "ERROR: ",
        IO.ANSI.reset(),
        IO.ANSI.white(),
        to_string(&1),
        IO.ANSI.reset()
      ]
    )
  end
end
