defmodule Electric.Migrations.Lexer do
  @moduledoc """
  """
  use LexLuthor
  #  defrule ~r/^(?=BEGIN)/,                             fn(e) -> :BEGIN end
  #  defrule ~r/^(?!CASE)[\s\S]*?((?=END)|(?=CASE))/, :BEGIN, fn(e) -> { :begin, e } end
  #  defrule ~r/^END/,                                       :BEGIN, fn(e) -> nil end

  defrule(~r/^(?!BEGIN)(?!CASE)[\s\S]*?((?=BEGIN)|(?=CASE)|;)/, fn e -> {:statement, e} end)
  defrule(~r/^\n/, fn e -> {:whitespace, e} end)
  defrule(~r/^(?=BEGIN)/, fn e -> :BEGIN end)
  defrule(~r/^(?=CASE)/, fn e -> :CASE end)

  defrule(~r/^(?!END)(?!CASE)[\s\S]*?((?=CASE)|(?=END))/, :BEGIN, fn e -> {:begin, e <> "END"} end)

  defrule(~r/^(?=CASE)/, :BEGIN, fn e -> :CASE end)
  defrule(~r/^END/, :BEGIN, fn e -> nil end)

  defrule(~r/^(?!END)(?!BEGIN)[\s\S]*?((?=BEGIN)|(?=END))/, :CASE, fn e -> {:case, e <> "END"} end)

  defrule(~r/^(?=BEGIN)/, :CASE, fn e -> :BEGIN end)
  defrule(~r/^END/, :CASE, fn e -> nil end)

  #  defrule ~r/^(?=BEGIN)/,                             fn(e) -> :BEGIN end
  #  defrule ~r/^[\s\S]*?(END)/, :BEGIN, fn(e) -> { :begin, e } end
  #  defrule ~r/^(?<=END)/,                                       :BEGIN, fn(e) -> nil end

  #  defrule ~r/;\s*/,                              fn(e) -> { :statement, e } end

  #  defrule ~r/^(?=CASE)/,                                      :BEGIN, fn(e) -> :CASE end

  #
  #  defrule ~r/^\n/,                       :BEGIN,        fn(e) -> nil end

  #  defrule ~r/^(?=CASE)/,                                            fn(e) -> :CASE end
  #  defrule ~r/^(?!BEGIN)[\s\S]*?(?=END)/,          :CASE,fn(e) -> { :case, e } end
  #  defrule ~r/^END/,                                       :CASE,fn(e) -> nil end

  #  defrule ~r/^(?=CASE)/,                                            fn(e) -> :CASE end
  #  defrule ~r/^(?!BEGIN)[\s\S]*?(END;)/,          :CASE,fn(e) -> { :case, e } end
  #  defrule ~r/^(?<=END;)./,                                       :CASE,fn(e) -> nil end
  #  defrule ~r/^\n/,                            :CASE,   fn(e) -> { :case, e } end

  #  defrule ~r/^\n/,                              fn(e) -> { :whitespace, e } end
  #  defrule ~r/;/,                              fn(e) -> { :statement, e } end
  #
  def get_statements(input) do
    cleaned = remove_comments(input)
    {:ok, tokens} = lex(cleaned)
    extract_statements(tokens) |> remove_ends()
  end

  defp get_next_statement_tokens(tokens) do
    with_index = Enum.with_index(tokens)

    statement_token_count =
      Enum.reduce_while(with_index, 0, fn {token, i}, counter ->
        next =
          if i == length(tokens) - 1 do
            nil
          else
            Enum.at(tokens, i + 1)
          end

        if next == nil do
          if token.name == :statement do
            {:halt, counter + 1}
          else
            {:halt, counter}
          end
        else
          case {token.name, next.name} do
            {:begin, _} ->
              {:cont, counter + 1}

            {:case, _} ->
              {:cont, counter + 1}

            {:statement, :begin} ->
              {:cont, counter + 1}

            {:statement, :case} ->
              {:cont, counter + 1}

            {:statement, _} ->
              {:halt, counter + 1}

            _ ->
              {:halt, counter}
          end
        end
      end)

    Enum.split(tokens, statement_token_count)
  end

  defp extract_statement_groups(tokens, groups) do
    {next_group, remains} = get_next_statement_tokens(tokens)
    extended_groups = groups ++ [next_group]

    if length(tokens) == length(remains) do
      {:error, "failed to get next statement"}
    else
      if remains == [] do
        {:ok, extended_groups}
      else
        extract_statement_groups(remains, extended_groups)
      end
    end
  end

  defp extract_statements(tokens) do
    filtered_tokens =
      Enum.filter(tokens, fn token ->
        token.name == :statement or token.name == :begin or token.name == :case
      end)

    case extract_statement_groups(filtered_tokens, []) do
      {:ok, statements_groups} ->
        for statements_group <- statements_groups do
          Enum.reduce(statements_group, "", fn token, acc ->
            segment = String.replace_leading(token.value, "\n", "")

            case token.name do
              :statement ->
                acc <> segment

              :begin ->
                "#{acc}#{segment}"

              :case ->
                "#{acc}#{segment}"
            end
          end)
        end

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp remove_ends(statements) do
    for statement <- statements do
      String.replace(statement, "ENDCASE", "CASE") |> String.replace("ENDBEGIN", "BEGIN")
    end
  end

  defp remove_comments(input) do
    input
    #    String.replace(input, ~r/--[^\n]*\n/, "\n") |> String.replace(~r/\/\*[\s\S]*?\*\//, " ")
  end
end
