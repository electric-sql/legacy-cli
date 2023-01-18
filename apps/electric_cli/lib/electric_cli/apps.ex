defmodule ElectricCli.Apps do
  alias ElectricCli.Client
  alias ElectricCli.Validate

  def can_show_app(_app, false) do
    :ok
  end

  def can_show_app(nil, _should_verify) do
    :ok
  end

  def can_show_app(app, true) do
    with :ok <- Validate.validate_slug(app),
         {:ok, %Req.Response{status: 200}} <- Client.get("apps/#{app}") do
      :ok
    else
      {:ok, %Req.Response{}} ->
        {:error, "invalid credentials",
         [
           "Did you run ",
           IO.ANSI.yellow(),
           "electric auth login EMAIL",
           IO.ANSI.reset(),
           " on this machine?"
         ]}

      {:error, {:invalid, _}} ->
        {:error, "invalid app id"}

      {:error, _exception} ->
        {:error, "couldn't connect to ElectricSQL servers"}
    end
  end
end
