defmodule Electric.Flags do
  @moduledoc """
  Share default flags.
  """

  @default_flags [
    help: [
      long: "--help",
      help: "Print usage docs",
      required: false
    ],
    verbose: [
      long: "--verbose",
      short: "-v",
      help: "Output more information about the client's actions",
      required: false
    ]
  ]

  def merge_flags(command_specific \\ []) do
    @default_flags
    |> Keyword.merge(command_specific)
  end

  def default_flags do
    @default_flags
  end
end
