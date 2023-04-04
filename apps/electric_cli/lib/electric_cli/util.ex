defmodule ElectricCli.Util do
  @moduledoc """
  Shared utility functions
  """

  def map_put_if(%{} = map, _key, _value, false) do
    map
  end

  def map_put_if(%{} = map, key, value, true) do
    Map.put(map, key, value)
  end

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

  def optionally_sort(items, true) do
    items
    |> Enum.sort()
  end

  def optionally_sort(items, false) do
    items
  end

  def get_existing_atom(s, err) when is_binary(s) do
    try do
      atom = String.to_existing_atom(s)

      {:ok, atom}
    rescue
      ArgumentError ->
        err
    end
  end

  # o_O
  def string_keyed_nested_map_from_nested_struct(schema) when is_struct(schema) do
    schema
    |> to_nested_map()
  end

  defp to_nested_map(schema) when is_struct(schema) do
    schema
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {"#{key}", to_nested_map(value)} end)
    |> Enum.into(%{})
  end

  defp to_nested_map(value) do
    cond do
      is_struct(value) -> to_nested_map(value)
      is_map(value) -> value
      is_list(value) -> Enum.map(value, &to_nested_map/1)
      true -> value
    end
  end

  def format_messages(type_of_message, messages) when is_list(messages) do
    case length(messages) do
      1 ->
        message = Enum.at(messages, 0)

        format_messages(type_of_message, message)

      n ->
        "There were #{n} #{type_of_message}:\n" <>
          Enum.join(messages, "\n")
    end
  end

  def format_messages(type_of_message, message) when is_atom(message) do
    format_messages(type_of_message, "#{message}")
  end

  def format_messages(type_of_message, message) do
    type_of_message =
      type_of_message
      |> String.replace_trailing("s", "")

    "There was an #{type_of_message}:\n" <> message
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
