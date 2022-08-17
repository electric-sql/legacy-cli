

defmodule MigrationsTest do
  use ExUnit.Case
  @trigger_template "ADD A TRIGGER FOR <table_name>;"

  describe "Finds create table instructions in sql" do

    test "find single create" do
      sql = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            """
      assert Electric.Contexts.Migrations.created_table_names(sql) == ["fish"]
    end

    test "find create without is exists" do
      sql = """
            CREATE TABLE fish (
            value TEXT PRIMARY KEY
            );
            """
      assert Electric.Contexts.Migrations.created_table_names(sql) == ["fish"]
    end

    test "find multiple creates" do
      sql = """
            --A comment:
            SOME OTHER RUBBISH;
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            SOME OTHER RUBBISH;
            CREATE TABLE cats (
            value TEXT PRIMARY KEY
            );
            """
      assert Electric.Contexts.Migrations.created_table_names(sql) == ["fish", "cats"]
    end
  end

  describe "template the triggers" do
    test "template a single name" do
      assert Electric.Contexts.Migrations.trigger_templated("fish", @trigger_template) == "ADD A TRIGGER FOR fish;"
    end
  end

  describe "adds_triggers to sql" do

    test "add a trigger" do

      sql = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            """
      expected = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            ADD A TRIGGER FOR fish;
            """

      assert Electric.Contexts.Migrations.add_triggers_to_sql(sql, @trigger_template) == expected
    end

        test "add a realistic trigger" do

      sql = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            """
      expected = """
CREATE TABLE IF NOT EXISTS fish (
value TEXT PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS _oplog (
  tablename String NOT NULL,
  optype String NOT NULL,
  oprowid String NOT NULL,
  newrow String,
  oldrow String,
  timestamp INTEGER
);

DROP TRIGGER IF EXISTS insert_fish_into_oplog;
CREATE TRIGGER insert_fish_into_oplog
   AFTER INSERT ON fish
BEGIN
  INSERT INTO _oplog (tablename, optype, oprowid, newrow, oldrow, timestamp)
VALUES
  ('fish','INSERT', new.rowid, json_object('value', new.value), NULL, NULL);
END;

DROP TRIGGER IF EXISTS update_fish_into_oplog;
CREATE TRIGGER update_fish_into_oplog
   AFTER UPDATE ON fish
BEGIN
  INSERT INTO _oplog (tablename, optype, oprowid, newrow, oldrow, timestamp)
VALUES
  ('fish','UPDATE', new.rowid, json_object('value', new.value), json_object('value', old.value), NULL);
END;

DROP TRIGGER IF EXISTS delete_fish_into_oplog;
CREATE TRIGGER delete_fish_into_oplog
   AFTER DELETE ON fish
BEGIN
  INSERT INTO _oplog (tablename, optype, oprowid, newrow, oldrow, timestamp)
VALUES
    ('fish','DELETE', new.rowid, NULL, json_object('value', old.value), NULL);
END;
"""

      templated = Electric.Contexts.Migrations.add_triggers_to_sql(sql, Electric.Contexts.Migrations.get_template())
#      IO.puts templated

      assert templated == expected
    end

    test "adding a trigger is idempotent" do

      sql = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            """
      expected = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            ADD A TRIGGER FOR fish;
            """
      sql = Electric.Contexts.Migrations.add_triggers_to_sql(sql, @trigger_template)
      assert Electric.Contexts.Migrations.add_triggers_to_sql(sql, @trigger_template) == expected
    end
  end
end


defmodule MigrationsFileTest do
  use ExUnit.Case
  @trigger_template "ADD A TRIGGER FOR <table_name>;"

  setup_all do
    tmp_dir = "tmp"
    File.rm_rf(tmp_dir)
    File.mkdir(tmp_dir)
  end

  describe "adds_triggers to sql files" do

    test "add a trigger to a sql file" do
      path = "test/support/migration.sql"
      tmp_path = "tmp/migration.sql"
      File.copy(path, tmp_path)
      Electric.Contexts.Migrations.add_triggers_to_file(tmp_path, @trigger_template)
      expected = """
            CREATE TABLE IF NOT EXISTS items (
              value TEXT PRIMARY KEY
            );
            ADD A TRIGGER FOR items;
            """
      modified = File.read!(tmp_path)
      assert modified == expected
    end

    test "add a trigger to all sql files in a folder" do
      path = "test/support/migration.sql"
      tmp_path = "tmp/migrations/migration.sql"
      File.mkdir("tmp/migrations")
      File.copy(path, tmp_path)
      Electric.Contexts.Migrations.add_triggers_to_folder("tmp/migrations", @trigger_template)
      expected = """
            CREATE TABLE IF NOT EXISTS items (
              value TEXT PRIMARY KEY
            );
            ADD A TRIGGER FOR items;
            """
      modified = File.read!(tmp_path)
      assert modified == expected
    end

    test "adding triggers is idempotent" do
      path = "test/support/migration.sql"
      tmp_path = "tmp/migrations/migration.sql"
      File.mkdir("tmp/migrations")
      File.copy(path, tmp_path)
      Electric.Contexts.Migrations.add_triggers_to_folder("tmp/migrations", @trigger_template)
      Electric.Contexts.Migrations.add_triggers_to_folder("tmp/migrations", @trigger_template)
      expected = """
            CREATE TABLE IF NOT EXISTS items (
              value TEXT PRIMARY KEY
            );
            ADD A TRIGGER FOR items;
            """
      modified = File.read!(tmp_path)
      assert modified == expected
    end

  end

end