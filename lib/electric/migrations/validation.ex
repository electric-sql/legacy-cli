defmodule Electric.Migrations.Validation do
  @moduledoc """

  """

  def validate(ordered_migrations) do

#    ast = case sql_ast_from_ordered_migrations(ordered_migrations) do
#      {:error, reason}
#    end


  end


#  def ensure_and_validate_original_sql(migration) do
#    with_body = ensure_original_body(migration)
#    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
#
#    case Exqlite.Sqlite3.execute(conn, with_body.original_body) do
#      :ok ->
#        with_body
#
#      {:error, reason} ->
#        %{with_body | error: reason}
#    end
#  end

end