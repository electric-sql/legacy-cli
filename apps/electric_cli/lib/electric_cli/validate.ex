defmodule ElectricCli.Validate do
  @slug_expr ~r/^[0-9a-z]+(?:-[0-9a-z]+)*$/

  def validate_slug(nil) do
    {:error, {:invalid, :required}}
  end

  def validate_slug(slug) when is_binary(slug) do
    with {:min_length, true} <- {:min_length, String.length(slug) > 2},
         {:max_length, true} <- {:max_length, String.length(slug) < 65},
         {:format, true} <- {:format, Regex.match?(@slug_expr, slug)} do
      :ok
    else
      {key, false} ->
        {:error, {:invalid, key}}
    end
  end
end
