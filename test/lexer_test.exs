defmodule MigrationsLexerTest do
  use ExUnit.Case

  describe "Can extract statements from SQL" do
    test "Find simple statements and comments" do
      sql = """
      -- this is a comment
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      /*
      This is also a comment
      */
      CREATE TABLE IF NOT EXISTS dogs (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      result = Electric.Migrations.Lexer.get_statements(sql)

      expected = [
        "CREATE TABLE IF NOT EXISTS fish (\nvalue TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
        " \nCREATE TABLE IF NOT EXISTS dogs (\nvalue TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;"
      ]

      assert result == expected
    end

    test "Find nested statements" do
      sql = """
      DROP TRIGGER IF EXISTS update_main_fish_into_oplog;
      CREATE TRIGGER update_main_fish_into_oplog
        AFTER UPDATE ON main.fish
        WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'fish', 'UPDATE', json_object('value', new.value), json_object('value', new.value, 'colour', new.colour), json_object('value', old.value, 'colour', old.colour), NULL);
      END;

      DROP TRIGGER IF EXISTS delete_main_fish_into_oplog;
      CREATE TRIGGER delete_main_fish_into_oplog
        AFTER DELETE ON main.fish
        WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'fish', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value, 'colour', old.colour), NULL);
      END;
      """

      result = Electric.Migrations.Lexer.get_statements(sql)

      assert Enum.at(result, 0) == "DROP TRIGGER IF EXISTS update_main_fish_into_oplog;"

      assert Enum.at(result, 1) <> "\n" == """
             CREATE TRIGGER update_main_fish_into_oplog
               AFTER UPDATE ON main.fish
               WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
             BEGIN
               INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
               VALUES ('main', 'fish', 'UPDATE', json_object('value', new.value), json_object('value', new.value, 'colour', new.colour), json_object('value', old.value, 'colour', old.colour), NULL);
             END;
             """

      assert Enum.at(result, 2) == "DROP TRIGGER IF EXISTS delete_main_fish_into_oplog;"

      assert Enum.at(result, 3) <> "\n" == """
             CREATE TRIGGER delete_main_fish_into_oplog
               AFTER DELETE ON main.fish
               WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
             BEGIN
               INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
               VALUES ('main', 'fish', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value, 'colour', old.colour), NULL);
             END;
             """
    end

    test "Find nested nested statements" do
      sql = """
      DROP TRIGGER IF EXISTS update_ensure_main_fish_primarykey;
      CREATE TRIGGER update_ensure_main_fish_primarykey
         BEFORE UPDATE ON main.fish
      BEGIN
        SELECT
          CASE
            WHEN old.value != new.value THEN
              RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')
          END;
      END;
      """

      [result1, result2] = Electric.Migrations.Lexer.get_statements(sql)

      expected = """
      CREATE TRIGGER update_ensure_main_fish_primarykey
         BEFORE UPDATE ON main.fish
      BEGIN
        SELECT
          CASE
            WHEN old.value != new.value THEN
              RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')
          END;
      END;
      """

      assert result2 <> "\n" == expected
    end
  end
end
