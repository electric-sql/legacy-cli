defmodule Electric.Migration do
  @moduledoc """
  A struct to hold information about a single migration
  """

  @migration_file_name "migration.sql"
  @satellite_file_name "satellite.sql"
  @postgres_file_name "postgres.sql"
  @enforce_keys [:name]
  defstruct name: "noname", src_folder: nil, original_body: nil, satellite_body: nil, error: nil

  @doc """
  The file path for this migration's original source within the migrations folder
  """
  def original_file_path(migration) do
    Path.join([migration.src_folder, migration.name, @migration_file_name])
  end

  @doc """
  The file path for this migration's satellite SQL file within the migrations folder
  """
  def satellite_file_path(migration) do
    Path.join([migration.src_folder, migration.name, @satellite_file_name])
  end

  @doc """
  The file path for this migration's PostgreSQL file within the migrations folder
  """
  def postgres_file_path(migration) do
    Path.join([migration.src_folder, migration.name, @postgres_file_name])
  end

  @doc """
  reads the original source from file
  """
  def ensure_original_body(migration) when migration.original_body == nil do
    sql = File.read!(original_file_path(migration))
    %{migration | original_body: sql}
  end

  def ensure_original_body(migration) when migration.original_body != nil do
    migration
  end

  @doc """
  reads the satellite source from file
  """
  def ensure_satellite_body(migration) when migration.satellite_body == nil do
    sql = File.read!(satellite_file_path(migration))
    %{migration | satellite_body: sql}
  end

  def ensure_satellite_body(migration) when migration.satellite_body != nil do
    migration
  end

  @doc """
  reads the satellite metadata from the file header and returns the metadata as a json serialisable map
  with_body: is a bool to ask for the satellite migration body itself to be included
  """
  def as_json_map(migration, body_style) do
    with_satellite_body = ensure_satellite_body(migration)
    metadata = get_satellite_metadata(with_satellite_body)

    case body_style do
      :none ->
        metadata

      :text ->
        Map.merge(metadata, %{
          "body" => with_satellite_body.satellite_body,
          "encoding" => "escaped"
        })

      :list ->
        body = with_satellite_body.satellite_body
        Map.merge(metadata, %{"body" => split_body_into_commands(body), "encoding" => "escaped"})
    end
  end

  defp split_body_into_commands(body) do
    regex = ~r/(?:--[^\n]*\n)|(?:\/\*[\s\S]*?\*\/)|([^\s][^;]+;)/
    matches = Regex.scan(regex, body)

    for match <- matches, length(match) > 1 do
      List.last(match)
    end
  end

  @doc """
  reads the satellite metadata from the file header
  """
  def get_satellite_metadata(migration) do
    with_satellite = ensure_satellite_body(migration)
    get_body_metadata(with_satellite.satellite_body)
  end

  @doc """
  reads the original metadata from the file header
  """
  def get_original_metadata(migration) do
    with_original = ensure_original_body(migration)
    get_body_metadata(with_original.original_body)
  end

  defp get_body_metadata(body) do
    regex = ~r/ElectricDB Migration[\s]*(.*?)[\s]*\*/
    matches = Regex.run(regex, body)

    if matches == nil do
      {:error, "no header"}
    else
      case Jason.decode(List.last(matches)) do
        {:ok, metadata} -> metadata["metadata"]
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def file_header(migration, hash, title) do
    case title do
      nil ->
        """
        /*
        ElectricDB Migration
        {"metadata": {"name": "#{migration.name}", "sha256": "#{hash}"}}
        */
        """

      _ ->
        """
        /*
        ElectricDB Migration
        {"metadata": {"title": "#{title}", "name": "#{migration.name}", "sha256": "#{hash}"}}
        */
        """
    end
  end
end
