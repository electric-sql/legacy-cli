defmodule ElectricMigrations.Sqlite.Lexer do
  @moduledoc """
  Simple regex and FSM-based lexer for SQL.
  """

  @doc """
  Split SQL into statements ignoring any comments.
  """
  @spec get_statements(input :: String.t()) :: [String.t()]
  def get_statements(input) do
    {_stack, breaks} =
      Enum.reduce(0..(String.length(input) - 1), {[], []}, fn index, {stack, breaks} ->
        step(input, index, stack, breaks)
      end)

    for break <- Enum.reverse(breaks) do
      {start, finish} = break

      String.slice(input, start..finish)
      |> remove_comments()
      |> String.trim()
    end
  end

  @doc """
  Remove all comments from given SQL.
  """
  @spec clean_up_sql(input :: String.t()) :: String.t()
  def clean_up_sql(input) do
    Enum.join(get_statements(input), "\n\n") <> "\n"
  end

  defp step(input, index, stack, breaks) do
    {_done, next} = String.split_at(input, index)

    stack =
      if String.starts_with?(next, "BEGIN") do
        [:begin | stack]
      else
        stack
      end

    stack =
      if String.starts_with?(next, "CASE") do
        [:case | stack]
      else
        stack
      end

    stack =
      if String.starts_with?(next, "END") do
        List.delete_at(stack, 0)
      else
        stack
      end

    breaks =
      if String.starts_with?(next, ";") and length(stack) == 0 do
        if length(breaks) == 0 do
          [{0, index} | breaks]
        else
          {_, previous} = List.first(breaks)
          [{previous + 1, index} | breaks]
        end
      else
        breaks
      end

    {stack, breaks}
  end

  defp remove_comments(input) do
    String.replace(input, ~r/\/\*[\s\S]*?(?:\z|\*\/)/, "\n")
    |> String.replace(~r/--[^\n]*(?:\z|\n)/, "\n")
  end
end
