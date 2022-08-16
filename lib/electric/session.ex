defmodule Electric.Session do
  @moduledoc """
  Manages session token on the user's local filesystem.
  """

  # Credentials are stored in a `.session-creds` file inside a
  # `.electric-sql` config folder in the user's home directory.
  @dirname ".electric-sql"
  @filename ".session-creds"

  defp file_path do
    folder_path()
    |> Path.join(@filename)
  end

  defp folder_path do
    dir =
      System.user_home()
      |> Path.join(@dirname)

    unless File.dir?(dir) do
      File.mkdir_p!(dir)
    end

    dir
  end

  defmodule Credentials do
    @enforce_keys [:email, :token]
    defstruct [
      :email,
      :token
    ]

    def new(%{} = attrs) do
      struct(__MODULE__, attrs)
    end
  end

  @doc """
  Read credentials from the local file storage.

  Returns `%Credentials{}` or `nil`.
  """
  def get do
    path = file_path()

    case File.read(path) do
      {:ok, contents} ->
        contents
        |> Jason.decode!(keys: :atoms!)
        |> Credentials.new()

      {:error, _reason} ->
        nil
    end
  end

  @doc """
  Write new credentials to the local file storage.

  Returns `:ok` or `{:error, reason}`.
  """
  def set(email, token) when is_binary(email) and is_binary(token) do
    creds = %Credentials{email: email, token: token}
    contents = Jason.encode!(creds)

    file_path()
    |> File.write(contents)
  end

  @doc """
  Write new credentials to the local file storage.

  Returns `:ok` or `{:error, reason}`.
  """
  def clear do
    path = file_path()

    File.rm(path)
  end
end
