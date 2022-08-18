defmodule Electric.Util do
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

  def format_success(message) do
    [:green, :bright, message, :reset]
    |> IO.ANSI.format()
  end
end
