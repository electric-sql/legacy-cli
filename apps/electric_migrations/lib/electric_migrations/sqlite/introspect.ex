defmodule ElectricMigrations.Sqlite.Introspect do
  alias Exqlite.Sqlite3
  alias ElectricMigrations.Ast

  @spec open_in_memory! :: Sqlite3.db()
  def open_in_memory!() do
    {:ok, conn} = Sqlite3.open(":memory:")
    conn
  end

  @spec stream_all_tables(Sqlite3.db(), list(String.t())) :: Enumerable.t(Ast.TableInfo.t())
  def stream_all_tables(conn, excluded \\ ["_electric_oplog"]) do
    query =
      "SELECT * FROM sqlite_master WHERE type='table'" <>
        Enum.map_join(excluded, fn _ -> " AND name != ?" end) <> ";"

    stream_query_results!(conn, query, excluded)
    |> Stream.map(fn result ->
      %Ast.TableInfo{
        type: result["type"],
        name: result["name"],
        rootpage: result["rootpage"],
        sql: result["sql"],
        tbl_name: result["tbl_name"]
      }
    end)
  end

  @spec stream_all_columns(Sqlite3.db(), String.t()) :: Enumerable.t(Ast.ColumnInfo.t())
  def stream_all_columns(conn, table_name) do
    stream_query_results!(conn, "PRAGMA table_info(#{table_name})")
    |> Stream.map(fn result ->
      %Ast.ColumnInfo{
        cid: result["cid"],
        name: result["name"],
        type: result["type"],
        notnull: result["notnull"] != 0,
        dflt_value: result["dflt_value"],
        pk: result["pk"],
        unique: nil,
        pk_desc: nil
      }
    end)
  end

  @spec stream_all_foreign_keys(Sqlite3.db(), String.t()) :: Enumerable.t(Ast.ForeignKeyInfo.t())
  def stream_all_foreign_keys(conn, table_name) do
    stream_query_results!(conn, "PRAGMA foreign_key_list(#{table_name});")
    |> Stream.map(fn result ->
      %Ast.ForeignKeyInfo{
        id: result["id"],
        seq: result["seq"],
        table: result["table"],
        from: result["from"],
        to: result["to"],
        on_update: result["on_update"],
        on_delete: result["on_delete"],
        match: result["match"]
      }
    end)
  end

  @spec stream_all_indices(Sqlite3.db(), String.t()) :: Enumerable.t(Ast.IndexInfo.t())
  def stream_all_indices(conn, table_name) do
    stream_query_results!(conn, "PRAGMA index_list(#{table_name});")
    |> Stream.map(fn result ->
      %Ast.IndexInfo{
        seq: result["seq"],
        name: result["name"],
        unique?: result["unique"] == 1,
        origin: origin(result["origin"]),
        partial?: result["partial"] == 1,
        columns: list_index_columns(conn, result["name"])
      }
    end)
  end

  defp origin("c"), do: :create_index
  defp origin("u"), do: :unique_constraint
  defp origin("pk"), do: :primary_key

  @spec list_index_columns(Sqlite3.db(), String.t()) :: list(Ast.IndexColumn.t())
  defp list_index_columns(conn, name) do
    stream_query_results!(conn, "PRAGMA index_xinfo(#{name});")
    |> Stream.map(fn result ->
      %Ast.IndexColumn{
        rank: result["seqno"],
        column_name: result["name"],
        collating_sequence: result["coll"],
        direction: if(result["desc"] == 1, do: :desc, else: :asc),
        key?: result["key"] == 1
      }
    end)
    |> Enum.to_list()
  end

  @doc """
  Executes a query with given bind parameters and streams resulting rows as maps
  with column names as keys.
  """
  @spec stream_query_results!(Sqlite3.db(), String.t(), [any()] | nil) ::
          Enumerable.t([%{required(String.t()) => binary() | number()}])
  def stream_query_results!(conn, query, params \\ nil) do
    Stream.resource(
      fn -> prepare_and_bind_statement!(conn, query, params) end,
      fn {statement, columns} ->
        case Sqlite3.step(conn, statement) do
          {:row, row} ->
            {[Enum.zip(columns, row) |> Map.new()], {statement, columns}}

          :done ->
            {:halt, statement}
        end
      end,
      &Sqlite3.release(conn, &1)
    )
  end

  defp prepare_and_bind_statement!(conn, query, params) do
    {:ok, statement} = Sqlite3.prepare(conn, query)
    :ok = Sqlite3.bind(conn, statement, params)

    {:ok, columns} = Sqlite3.columns(conn, statement)

    {statement, columns}
  end
end
