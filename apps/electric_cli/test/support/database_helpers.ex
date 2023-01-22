defmodule ElectricCli.DatabaseHelpers do
  @moduledoc """
  Provides an `init_schema/1` function that sets up the test database
  with tables and metadata that's now setup by satellite, but that we
  need to duplicate here in order to bootstrap a database and validate
  that we're correctly adding the triggers.
  """
  alias Exqlite.Sqlite3

  @init_statements """
  -- The ops log table
  CREATE TABLE IF NOT EXISTS _electric_oplog (
    rowid INTEGER PRIMARY KEY AUTOINCREMENT,
    namespace String NOT NULL,
    tablename String NOT NULL,
    optype String NOT NULL,
    primaryKey String NOT NULL,
    newRow String,
    oldRow String,
    timestamp TEXT
  );

  -- Somewhere to keep our metadata
  CREATE TABLE IF NOT EXISTS _electric_meta (
    key TEXT PRIMARY KEY,
    value BLOB
  );

  -- Somewhere to track migrations
  CREATE TABLE IF NOT EXISTS _electric_migrations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    sha256 TEXT NOT NULL,
    applied_at TEXT NOT NULL
  );

  -- Initialisation of the metadata table
  INSERT INTO _electric_meta (key, value) VALUES
    ('compensations', 0),
    ('lastAckdRowId','0'),
    ('lastSentRowId', '0'),
    ('lsn', 'MA=='),
    ('clientId', '');
  """

  def init_schema(conn) do
    conn
    |> Sqlite3.execute(@init_statements)
  end
end
