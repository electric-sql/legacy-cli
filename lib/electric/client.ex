defmodule Electric.Client do
  @moduledoc """
  HTTP client to talk to the Console API.
  """

  alias Electric.Session
  alias Electric.Session.Credentials

  alias Electric.Util

  @default_base_url "https://console.electric-sql.com/api/v1/"

  def base_url do
    Application.get_env(:electric_sql_cli, :base_url, @default_base_url)
  end

  def base_req do
    Req.new(base_url: base_url())
  end

  @doc """
  Send an authenticated GET.request to the API.
  """
  def get("/" <> path), do: get(path)

  def get(path) do
    base_req()
    |> request(method: :get, url: path)
  end

  @doc """
  Send an authenticated POST.request to the API with a JSON payload.
  """
  def post("/" <> path, payload), do: post(path, payload)

  def post(path, payload) do
    base_req()
    |> request(method: :post, url: path, json: payload)
  end

  @doc """
  Send an authenticated PUT.request to the API with a JSON payload.
  """
  def put("/" <> path, payload), do: put(path, payload)

  def put(path, payload) do
    base_req()
    |> request(method: :put, url: path, json: payload)
  end

  @doc """
  Make an authenticated request to the API..
  """
  def request(%Req.Request{} = req, options \\ [], should_refresh \\ true) do
    creds = Session.get()

    # If we have stored credentials, then add to the
    # request as a bearer token.
    options =
      case creds do
        %Credentials{token: token} ->
          Keyword.merge(options, auth: {:bearer, token})

        _alt ->
          options
      end

    response =
      req
      |> Req.request(options)

    # Intercept the response and handle the case where
    # we provided a bearer token but got an unauthenticated
    # response -- which means the token is invalid, which
    # for non-malicious use means it has expired.
    with {true, %Credentials{}} <- {should_refresh, creds},
         {:ok, %{status: 401}} <- response,
         :ok <- renew_credentials(creds) do
      # Retry the request wthout refreshing if it 401s again.
      request(req, options, false)
    else
      _alt ->
        response
    end
  end

  defp renew_credentials(%Credentials{refresh_token: refresh_token}) do
    path = "auth/renew"

    payload = %{
      data: refresh_token
    }

    case Req.request(base_req(), method: :post, url: path, json: payload) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        set_credentials(data)

      _alt ->
        :ok = Session.clear()

        :failed
    end
  end

  defp set_credentials(data) do
    data
    |> Util.rename_map_key("refreshToken", "refresh_token")
    |> Session.set()
  end
end
