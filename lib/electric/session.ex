defmodule Electric.Session do
  @moduledoc """
  Manages session token on the user's local filesystem.
  """
  use Memoize

  # Credentials are stored in a `.session-creds` file inside a
  # `.electric-sql` config folder in the user's home directory.
  @dirname "electric"
  @filename "credentials.json"

  defp file_path do
    state_path()
    |> Path.join(@filename)
  end

  @doc """
  Gives the base directory for the session state.

  If set will use the environment variable `ELECTRIC_STATE_HOME`. Otherwise uses
  `$XDG_STATE_HOME/electric` which defaults to `$HOME/.local/state/electric`.
  """
  def state_path do
    {source, path} =
      case System.get_env("ELECTRIC_STATE_HOME", "") do
        "" ->
          case System.fetch_env("XDG_STATE_HOME") do
            {:ok, path} ->
              {"XDG_STATE_HOME", Path.join(path, @dirname)}

            :error ->
              home = System.get_env("HOME", System.user_home!())
              {nil, Path.join([home, ".local/state", @dirname])}
          end

        path ->
          {"ELECTRIC_STATE_HOME", path}
      end

    if File.exists?(path) do
      unless File.dir?(path) do
        message =
          IO.iodata_to_binary([
            "State path '#{path}' is not a directory",
            if(source, do: " (set from $#{source})", else: "")
          ])

        raise RuntimeError, message: message
      end
    else
      File.mkdir_p!(path)
    end

    path
  end

  defmodule Credentials do
    @derive Jason.Encoder
    @enforce_keys [:id, :email, :token, :refresh_token]
    defstruct [
      :id,
      :email,
      :token,
      :refresh_token
    ]

    use ExConstructor
  end

  @doc """
  Read credentials from the local file storage.

  Returns `%Credentials{}` or `nil`.
  """
  defmemo get do
    path = file_path()

    case File.read(path) do
      {:ok, contents} ->
        contents
        |> Jason.decode!()
        |> Credentials.new()

      {:error, _reason} ->
        nil
    end
  end

  @doc """
  Write new credentials to the local file storage.

  Returns `:ok` or `{:error, reason}`.
  """
  def set(data) do
    path = file_path()

    creds = Credentials.new(data)
    contents = Jason.encode!(creds)

    case File.write(path, contents) do
      :ok ->
        Memoize.invalidate(__MODULE__, :get)

        :ok

      err ->
        err
    end
  end

  @doc """
  Write new credentials to the local file storage.

  Returns `:ok` or `{:error, reason}`.
  """
  def clear do
    path = file_path()

    case File.rm(path) do
      :ok ->
        Memoize.invalidate(__MODULE__, :get)

        :ok

      err ->
        err
    end
  end
end
