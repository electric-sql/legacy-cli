defmodule Electric.Flags do
  @moduledoc """
  Share default flags.
  """

  @default_flags [
    help: [
      long: "--help",
      help: "Print usage docs",
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
