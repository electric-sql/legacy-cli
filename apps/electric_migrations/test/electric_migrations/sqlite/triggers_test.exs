defmodule ElectricMigrations.Sqlite.TriggersTest do
  use ExUnit.Case
  alias ElectricMigrations.Sqlite.Triggers

  @trigger_template EEx.compile_string("""
                    <%= original_sql %><%= for {table_full_name, _table} <- tables do %>
                    --ADD A TRIGGER FOR <%= table_full_name %>;<% end %>
                    """)

  describe "add_triggers_to_last_migration/2" do
    test "adds triggers based on the template for each table in the migration" do
      sql = """
      CREATE TABLE IF NOT EXISTS foo (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS bar (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      # NOTE: Ordering is not preserved when adding triggers
      expected = """
      #{sql}
      --ADD A TRIGGER FOR main.bar;
      --ADD A TRIGGER FOR main.foo;
      """

      assert Triggers.add_triggers_to_last_migration(
               [%{"name" => "test1", "original_body" => sql}],
               @trigger_template
             ) == {expected, nil}
    end
  end
end
