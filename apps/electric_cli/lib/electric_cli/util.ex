defmodule ElectricCli.Util do
  @moduledoc """
  Shared utility functions
  """

  def rename_map_key(%{} = map, old_key, new_key) do
    case Map.has_key?(map, old_key) do
      true -> rename_map_key!(map, old_key, new_key)
      false -> map
    end
  end

  def rename_map_key!(%{} = map, old_key, new_key) do
    {value, map} = Map.pop!(map, old_key)

    map
    |> Map.put(new_key, value)
  end

  def take_unless_nil(map, keys) do
    map
    |> Map.take(keys)
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      case is_nil(v) do
        true -> acc
        false -> Map.put(acc, k, v)
      end
    end)
  end

  def format_success(message) do
    [:green, :bright, message]
    |> IO.ANSI.format()
    |> IO.iodata_to_binary()
  end

  def enable_verbose(verbose?) do
    Application.put_env(:electric_cli, :verbose, verbose?)
    verbose("Enabling verbose output")
  end

  def verbose? do
    Application.get_env(:electric_cli, :verbose, false)
  end

  def verbose(message) do
    if verbose?() do
      IO.puts(IO.ANSI.format([:blue, "∷ ", message]))
    end
  end
end
