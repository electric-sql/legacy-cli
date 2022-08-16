defmodule Electric.Client do
  @moduledoc """
  HTTP client to talk to the Console API.
  """

  @default_base_url (case Mix.env() do
                       :prod ->
                         "https://console.electric-sql.com/api/v1"

                       _ ->
                         "http://localhost:4000/api/v1"
                     end)

  @base_url System.get_env("ELECTRIC_BASE_URL", @default_base_url)

  def base_req do
    Req.new(base_url: @base_url)
  end

  def post_json(path, payload) do
    base_req()
    |> Req.request(method: :post, url: path, json: payload)
    |> IO.inspect()
  end
end
