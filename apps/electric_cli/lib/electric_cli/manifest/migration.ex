defmodule ElectricCli.Manifest.Migration do
  alias __MODULE__

  @derive {Jason.Encoder, except: [:original_body, :satellite_raw, :status]}
  @type t() :: %Migration{
          encoding: binary(),
          name: binary(),
          original_body: binary(),
          postgres_body: binary(),
          satellite_body: [binary()],
          satellite_raw: binary(),
          sha256: binary(),
          status: binary(),
          title: binary()
        }
  @enforce_keys [
    :encoding,
    :name,
    :satellite_body,
    :sha256,
    :title
  ]
  defstruct [
    :encoding,
    :name,
    :original_body,
    :postgres_body,
    :satellite_body,
    :satellite_raw,
    :sha256,
    :status,
    :title
  ]

  use ExConstructor

  @upload_keys [
    :name,
    :original_body,
    :satellite_body,
    :sha256,
    :title
  ]

  def upload_data(%Migration{} = migration) do
    migration
    |> Map.take(@upload_keys)
  end
end
