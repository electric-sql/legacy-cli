defmodule ElectricMigrations.Sqlite.LexerTest do
  use ExUnit.Case
  alias ElectricMigrations.Sqlite.Lexer

  describe "get_statements/1" do
    test "finds simple statements with comments" do
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

      result = Lexer.get_statements(sql)

      expected = [
        "CREATE TABLE IF NOT EXISTS fish (\nvalue TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
        "CREATE TABLE IF NOT EXISTS dogs (\nvalue TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;"
      ]

      assert result == expected
    end

    test "finds simple without statements" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS dogs (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      result = Lexer.get_statements(sql)

      expected = [
        "CREATE TABLE IF NOT EXISTS fish (\nvalue TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
        "CREATE TABLE IF NOT EXISTS dogs (\nvalue TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;"
      ]

      assert result == expected
    end

    test "finds nested statements" do
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

      [drop1, create1, drop2, create2] = Lexer.get_statements(sql)

      assert drop1 == "DROP TRIGGER IF EXISTS update_main_fish_into_oplog;"

      assert create1 <> "\n" == """
             CREATE TRIGGER update_main_fish_into_oplog
               AFTER UPDATE ON main.fish
               WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
             BEGIN
               INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
               VALUES ('main', 'fish', 'UPDATE', json_object('value', new.value), json_object('value', new.value, 'colour', new.colour), json_object('value', old.value, 'colour', old.colour), NULL);
             END;
             """

      assert drop2 == "DROP TRIGGER IF EXISTS delete_main_fish_into_oplog;"

      assert create2 <> "\n" == """
             CREATE TRIGGER delete_main_fish_into_oplog
               AFTER DELETE ON main.fish
               WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
             BEGIN
               INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
               VALUES ('main', 'fish', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value, 'colour', old.colour), NULL);
             END;
             """
    end

    test "correctly handles CASE inside BEGIN statements" do
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

      [_result1, result2] = Lexer.get_statements(sql)

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

    test "correctly handles CASE inside CASE statements" do
      sql = """
      DROP TRIGGER IF EXISTS update_ensure_main_fish_primarykey;
      CREATE TRIGGER update_ensure_main_fish_primarykey
         BEFORE UPDATE ON main.fish
      BEGIN
        SELECT
          CASE
            WHEN old.value != new.value THEN
              CASE
                WHEN old.value == "hello" THEN
                  RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')
              END
              RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')
          END;
      END;
      """

      [_result1, result2] = Lexer.get_statements(sql)

      expected = """
      CREATE TRIGGER update_ensure_main_fish_primarykey
         BEFORE UPDATE ON main.fish
      BEGIN
        SELECT
          CASE
            WHEN old.value != new.value THEN
              CASE
                WHEN old.value == "hello" THEN
                  RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')
              END
              RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')
          END;
      END;
      """

      assert result2 <> "\n" == expected
    end
  end

  describe "strip_comments/1" do
    test "removes all comments from SQL file" do
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

      result = Lexer.strip_comments(sql)

      assert result == """
             CREATE TABLE IF NOT EXISTS fish (
             value TEXT PRIMARY KEY
             ) STRICT, WITHOUT ROWID;

             CREATE TABLE IF NOT EXISTS dogs (
             value TEXT PRIMARY KEY
             ) STRICT, WITHOUT ROWID;
             """
    end
  end
end
