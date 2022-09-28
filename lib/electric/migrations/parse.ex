defmodule Electric.Migrations.Parse do
  @moduledoc """
  hello
  """

  @doc false
  def sql_ast_from_migration_set(migrations) do
    case ast_from_ordered_migrations(migrations) do
      {ast, []} ->
        ast

      {ast, errors} ->
        {:error, errors}
    end
  end

  @doc false
  def ast_from_ordered_migrations(migrations) do
    namespace = "main"
    # get all the table names
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    sql_errors =
      Enum.flat_map(migrations, fn migration ->
        case Exqlite.Sqlite3.execute(conn, migration.original_body) do
          {:error, reason} -> ["In migration #{migration.name} SQL error: #{reason}"]
          :ok -> []
        end
      end)

    if length(sql_errors) > 0 do
      {:error, sql_errors}
    else
      index_info = all_index_info_from_connection(conn)

      {:ok, statement} =
        Exqlite.Sqlite3.prepare(
          conn,
          "SELECT * FROM sqlite_master WHERE type='table' AND name!='_electric_oplog';"
        )

      info = get_rows_while(conn, statement, [])
      :ok = Exqlite.Sqlite3.release(conn, statement)

      # for each table
      infos =
        for [type, name, tbl_name, rootpage, sql] <- info do
          validation_fails = check_sql(tbl_name, sql)

          # column names
          {:ok, info_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{tbl_name});")
          columns = Enum.reverse(get_rows_while(conn, info_statement, []))

          column_names =
            for [_cid, name, _type, _notnull, _dflt_value, _pk] <- columns do
              name
            end

          column_infos =
            for [cid, name, type, notnull, dflt_value, pk] <- columns, into: %{} do
              {cid,
               %{
                 :cid => cid,
                 :name => name,
                 :type => type,
                 :notnull => notnull,
                 :unique => is_unique(name, index_info["#{namespace}.#{tbl_name}"]),
                 :pk_desc => is_primary_desc(name, index_info["#{namespace}.#{tbl_name}"]),
                 :dflt_value => dflt_value,
                 :pk => pk
               }}
            end

          # private keys columns
          private_key_column_names =
            for [_cid, name, _type, _notnull, _dflt_value, pk] when pk == 1 <- columns do
              name
            end

          # foreign keys
          {:ok, foreign_statement} =
            Exqlite.Sqlite3.prepare(conn, "PRAGMA foreign_key_list(#{tbl_name});")

          foreign_keys_rows = get_rows_while(conn, foreign_statement, [])

          foreign_keys =
            for [id, seq, table, from, to, on_update, on_delete, match] <- foreign_keys_rows do
              %{
                :child_key => from,
                :parent_key => to,
                :table => "#{namespace}.#{table}"
              }
            end

          foreign_keys_info =
            for [id, seq, table, from, to, on_update, on_delete, match] <- foreign_keys_rows do
              %{
                :id => id,
                :seq => seq,
                :table => table,
                :from => from,
                :to => to,
                :on_update => on_update,
                :on_delete => on_delete,
                :match => match
              }
            end

          %{
            :table_name => tbl_name,
            :table_info => %{
              type: type,
              name: name,
              tbl_name: tbl_name,
              rootpage: rootpage,
              sql: sql
            },
            :columns => column_names,
            :namespace => namespace,
            :primary => private_key_column_names,
            :foreign_keys => foreign_keys,
            :column_infos => column_infos,
            :foreign_keys_info => foreign_keys_info,
            :validation_fails => validation_fails
          }
        end

      ast = Enum.into(infos, %{}, fn info -> {"#{namespace}.#{info.table_name}", info} end)

      validation_fails =
        for info <- infos, length(info.validation_fails) > 0 do
          info.validation_fails
        end

      {ast, List.flatten(validation_fails)}
    end
  end

  def check_sql(table_name, sql) do
    validation_fails = []
    lower = String.downcase(sql)

    validation_fails =
      if !String.contains?(lower, "strict") do
        [
          "The table #{table_name} is not STRICT. Add the STRICT option at the end of the create table statement"
          | validation_fails
        ]
      else
        validation_fails
      end

    validation_fails =
      if !String.contains?(lower, "without rowid") do
        [
          "The table #{table_name} is not WITHOUT ROWID. Add the WITHOUT ROWID option at the end of the create table statement and make sure you also specify a primary key"
          | validation_fails
        ]
      else
        validation_fails
      end
  end

  def all_index_info(all_migrations) do
    namespace = "main"
    # get all the table names
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    for migration <- all_migrations do
      :ok = Exqlite.Sqlite3.execute(conn, migration)
    end

    all_index_info_from_connection(conn)
  end

  defp all_index_info_from_connection(conn) do
    namespace = "main"

    {:ok, statement} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT * FROM sqlite_master WHERE type='index';"
      )

    info = get_rows_while(conn, statement, [])
    :ok = Exqlite.Sqlite3.release(conn, statement)

    # for each table
    infos =
      for [type, name, tbl_name, rootpage, sql] <- info, into: %{} do
        # column names
        {:ok, info_statement} = Exqlite.Sqlite3.prepare(conn, "PRAGMA index_list(#{tbl_name});")
        indexes = Enum.reverse(get_rows_while(conn, info_statement, []))

        index_infos =
          for [seq, name, unique, origin, partial] <- indexes, into: %{} do
            {:ok, col_info_statement} =
              Exqlite.Sqlite3.prepare(conn, "PRAGMA index_xinfo(#{name});")

            index_columns = Enum.reverse(get_rows_while(conn, col_info_statement, []))

            index_column_infos =
              for [seqno, cid, name, desc, coll, key] <- index_columns do
                %{
                  :seqno => seqno,
                  :cid => cid,
                  :name => name,
                  :desc => desc,
                  :coll => coll,
                  :key => key
                }
              end

            {seq,
             %{
               :seq => seq,
               :name => name,
               :unique => unique,
               :origin => origin,
               :partial => partial,
               :columns => index_column_infos
             }}
          end

        {"main.#{tbl_name}", index_infos}
      end
  end

  defp get_rows_while(conn, statement, rows) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, row} ->
        get_rows_while(conn, statement, [row | rows])

      :done ->
        rows
    end
  end

  defp is_unique(column_name, indexes) do
    case indexes do
      nil ->
        false

      _ ->
        matching_unique_indexes =
          for {seq, info} <- indexes do
            case info.origin do
              "u" ->
                cols =
                  for key_column <- info.columns do
                    key_column.key == 1 && key_column.name == column_name
                  end

                Enum.any?(cols)

              _ ->
                false
            end
          end

        Enum.any?(matching_unique_indexes)
    end
  end

  defp is_primary_desc(column_name, indexes) do
    case indexes do
      nil ->
        false

      _ ->
        matching_desc_indexes =
          for {seq, info} <- indexes do
            case info.origin do
              "pk" ->
                cols =
                  for key_column <- info.columns do
                    key_column.key == 1 && key_column.name == column_name && key_column.desc == 1
                  end

                Enum.any?(cols)

              _ ->
                false
            end
          end

        Enum.any?(matching_desc_indexes)
    end
  end
end
