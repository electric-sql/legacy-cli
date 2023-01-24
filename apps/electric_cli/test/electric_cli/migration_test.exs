defmodule ElectricCli.MigrationsTest do
  use ExUnit.Case, async: false

  alias ElectricCli.DatabaseHelpers
  alias ElectricCli.Migrations
  alias ElectricMigrations.Sqlite.Triggers

  @trigger_template EEx.compile_string(
                      "<%= original_sql %><%= for {table_full_name, _table} <- tables do %>--ADD A TRIGGER FOR <%= table_full_name %>;<% end %>\n"
                    )

  defp electric_conn do
    with {:ok, conn} <- Exqlite.Sqlite3.open(":memory:"),
         :ok <- DatabaseHelpers.init_schema(conn) do
      {:ok, conn}
    end
  end

  describe "adds_triggers to sql" do
    test "add a trigger" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      expected =
        {"""
         CREATE TABLE IF NOT EXISTS fish (
         value TEXT PRIMARY KEY
         ) STRICT, WITHOUT ROWID;
         --ADD A TRIGGER FOR main.fish;
         """, nil}

      assert Triggers.add_triggers_to_last_migration(
               [%{name: "test1", original_body: sql}],
               @trigger_template
             ) ==
               expected
    end

    test "adding a trigger is valid sql" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Triggers.add_triggers_to_last_migration(
          [%{name: "test1", original_body: sql}],
          Migrations.satellite_template()
        )

      assert is_valid_sql(sql) == :ok
    end
  end

  def is_valid_sql(sql) do
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
    Exqlite.Sqlite3.execute(conn, sql)
  end

  describe "Triggers works as expected" do
    test "templating" do
      original_sql = """
      Some rubbish
      """

      tables = %{
        "main.fish" => %{
          :namespace => "main",
          :table_name => "fish",
          :primary => ["id", "colour"],
          :foreign_keys => [],
          :columns => ["id", "colour"]
        },
        "main.cats" => %{
          :namespace => "main",
          :table_name => "cats",
          :primary => ["id"],
          :foreign_keys => [
            %{:child_key => "favourite", :parent_key => "id", :table => "main.fish"}
          ],
          :columns => ["id", "name", "favourite"]
        }
      }

      templated =
        Triggers.template_all_the_things(
          original_sql,
          tables,
          Migrations.satellite_template(),
          true
        )

      expected = """
      Some rubbish

      /*---------------------------------------------
      Below are templated triggers added by Satellite
      ---------------------------------------------*/


      -- These are toggles for turning the triggers on and off
      DROP TABLE IF EXISTS _electric_trigger_settings;
      CREATE TABLE _electric_trigger_settings(tablename STRING PRIMARY KEY, flag INTEGER);
      INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.cats', 1);
      INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.fish', 1);


      /* Triggers for table cats */

      -- Ensures primary key is immutable
      DROP TRIGGER IF EXISTS update_ensure_main_cats_primarykey;
      CREATE TRIGGER update_ensure_main_cats_primarykey
         BEFORE UPDATE ON main.cats
      BEGIN
        SELECT
          CASE
            WHEN old.id != new.id THEN
              RAISE (ABORT,'cannot change the value of column id as it belongs to the primary key')
          END;
      END;

      -- Triggers that add INSERT, UPDATE, DELETE operation to the _opslog table

      DROP TRIGGER IF EXISTS insert_main_cats_into_oplog;
      CREATE TRIGGER insert_main_cats_into_oplog
         AFTER INSERT ON main.cats
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.cats')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'cats', 'INSERT', json_object('id', new.id), json_object('id', new.id, 'name', new.name, 'favourite', new.favourite), NULL, NULL);
      END;

      DROP TRIGGER IF EXISTS update_main_cats_into_oplog;
      CREATE TRIGGER update_main_cats_into_oplog
         AFTER UPDATE ON main.cats
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.cats')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'cats', 'UPDATE', json_object('id', new.id), json_object('id', new.id, 'name', new.name, 'favourite', new.favourite), json_object('id', old.id, 'name', old.name, 'favourite', old.favourite), NULL);
      END;

      DROP TRIGGER IF EXISTS delete_main_cats_into_oplog;
      CREATE TRIGGER delete_main_cats_into_oplog
         AFTER DELETE ON main.cats
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.cats')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'cats', 'DELETE', json_object('id', old.id), NULL, json_object('id', old.id, 'name', old.name, 'favourite', old.favourite), NULL);
      END;

      -- Triggers for foreign key compensations

      DROP TRIGGER IF EXISTS compensation_insert_main_cats_favourite_into_oplog;
      CREATE TRIGGER compensation_insert_main_cats_favourite_into_oplog
         AFTER INSERT ON main.cats
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish') AND
              1 == (SELECT value from _electric_meta WHERE key == 'compensations')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        SELECT 'main', 'fish', 'UPDATE', json_object('id', id, 'colour', colour), json_object('id', id, 'colour', colour), NULL, NULL
        FROM main.fish WHERE id = new.favourite;
      END;

      DROP TRIGGER IF EXISTS compensation_update_main_cats_favourite_into_oplog;
      CREATE TRIGGER compensation_update_main_cats_favourite_into_oplog
         AFTER UPDATE ON main.cats
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish') AND
              1 == (SELECT value from _electric_meta WHERE key == 'compensations')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        SELECT 'main', 'fish', 'UPDATE', json_object('id', id, 'colour', colour), json_object('id', id, 'colour', colour), NULL, NULL
        FROM main.fish WHERE id = new.favourite;
      END;


      /* Triggers for table fish */

      -- Ensures primary key is immutable
      DROP TRIGGER IF EXISTS update_ensure_main_fish_primarykey;
      CREATE TRIGGER update_ensure_main_fish_primarykey
         BEFORE UPDATE ON main.fish
      BEGIN
        SELECT
          CASE
            WHEN old.id != new.id THEN
              RAISE (ABORT,'cannot change the value of column id as it belongs to the primary key')
            WHEN old.colour != new.colour THEN
              RAISE (ABORT,'cannot change the value of column colour as it belongs to the primary key')
          END;
      END;

      -- Triggers that add INSERT, UPDATE, DELETE operation to the _opslog table

      DROP TRIGGER IF EXISTS insert_main_fish_into_oplog;
      CREATE TRIGGER insert_main_fish_into_oplog
         AFTER INSERT ON main.fish
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'fish', 'INSERT', json_object('id', new.id, 'colour', new.colour), json_object('id', new.id, 'colour', new.colour), NULL, NULL);
      END;

      DROP TRIGGER IF EXISTS update_main_fish_into_oplog;
      CREATE TRIGGER update_main_fish_into_oplog
         AFTER UPDATE ON main.fish
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'fish', 'UPDATE', json_object('id', new.id, 'colour', new.colour), json_object('id', new.id, 'colour', new.colour), json_object('id', old.id, 'colour', old.colour), NULL);
      END;

      DROP TRIGGER IF EXISTS delete_main_fish_into_oplog;
      CREATE TRIGGER delete_main_fish_into_oplog
         AFTER DELETE ON main.fish
         WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.fish')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'fish', 'DELETE', json_object('id', old.id, 'colour', old.colour), NULL, json_object('id', old.id, 'colour', old.colour), NULL);
      END;\n\n\n\n
      """

      assert templated == expected
    end

    test "tests op table created" do
      {:ok, conn} = electric_conn()

      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Triggers.add_triggers_to_last_migration(
          [%{name: "test1", original_body: sql}],
          Migrations.satellite_template()
        )

      :ok = Exqlite.Sqlite3.execute(conn, sql)

      {:ok, statement} =
        Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type='table';")

      names = get_while(conn, statement, [])

      assert MapSet.new(names) ==
               MapSet.new([
                 "_electric_oplog",
                 "_electric_meta",
                 "_electric_migrations",
                 "_electric_trigger_settings",
                 "fish",
                 "sqlite_sequence"
               ])
    end

    test "tests using namespaces" do
      {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

      sql = """
      CREATE TABLE IF NOT EXISTS main.fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      :ok = Exqlite.Sqlite3.execute(conn, sql)

      {:ok, statement} =
        Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type='table';")

      names = get_while(conn, statement, [])

      assert MapSet.new(names) == MapSet.new(["fish"])
    end

    test "tests triggers create op log entries" do
      {:ok, conn} = electric_conn()

      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Triggers.add_triggers_to_last_migration(
          [%{name: "test1", original_body: sql}],
          Migrations.satellite_template()
        )

      :ok = Exqlite.Sqlite3.execute(conn, sql)

      ## adding a fish
      :ok = Exqlite.Sqlite3.execute(conn, "insert into fish (value) values ('abcdefg')")

      {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM _electric_oplog;")
      ops = get_while_more(conn, statement, [])

      [_rowid, _namespace, tablename, optype, primaryKey, newRow, oldRow, _timestamp] =
        Enum.at(ops, 0)

      assert tablename == "fish"
      assert optype == "INSERT"
      assert primaryKey == "{\"value\":\"abcdefg\"}"
      assert newRow == "{\"value\":\"abcdefg\"}"
      assert oldRow == nil
    end

    test "tests triggers work as statements" do
      {:ok, conn} = electric_conn()

      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Triggers.add_triggers_to_last_migration(
          [%{name: "test1", original_body: sql}],
          Migrations.satellite_template()
        )

      commands = ElectricMigrations.Sqlite.get_statements(sql)

      for command <- commands do
        :ok = Exqlite.Sqlite3.execute(conn, command)
      end

      ## adding a red fish
      :ok =
        Exqlite.Sqlite3.execute(
          conn,
          "insert into fish (value, colour) values ('abcdefg', 'red')"
        )

      {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM _electric_oplog;")
      ops = get_while_more(conn, statement, [])

      [_rowid, _namespace, tablename, optype, primaryKey, newRow, oldRow, _timestamp] =
        Enum.at(ops, 0)

      assert tablename == "fish"
      assert optype == "INSERT"
      assert primaryKey == "{\"value\":\"abcdefg\"}"
      assert newRow == "{\"value\":\"abcdefg\",\"colour\":\"red\"}"
      assert oldRow == nil
    end

    test "stripping comments" do
      sql = """
      -- This is a comment
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      /* a star comment */
      CREATE TABLE IF NOT EXISTS cat (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      /*
      a multiline
      star comment
      */
      -- Another one liner
      CREATE TABLE IF NOT EXISTS dog (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      sql2 = "--Yet another one liner"

      sql = sql <> sql2

      stripped = ElectricMigrations.Sqlite.strip_comments(sql)

      expected = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS cat (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS dog (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      assert stripped == expected
    end

    test "stripping comments with unterminated * comments" do
      sql = """
      -- This is a comment
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      /* a star comment */
      CREATE TABLE IF NOT EXISTS cat (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      /*
      a multiline
      star comment
      */
      -- Another one liner
      CREATE TABLE IF NOT EXISTS dog (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      sql2 = "/*Yet another one liner"

      sql = sql <> sql2

      stripped = ElectricMigrations.Sqlite.strip_comments(sql)

      expected = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS cat (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS dog (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      assert stripped == expected
    end

    test "tests stripping single line comments" do
      str1 =
        "-- Somewhere to keep our metadata\nCREATE TABLE IF NOT EXISTS _electric_meta (\n  key TEXT PRIMARY KEY,\n  value BLOB\n);"

      str2 =
        "\n\n/*---------------------------------------------\nBelow are templated triggers added by Satellite\n---------------------------------------------*/\n\n-- The ops log table\nCREATE TABLE IF NOT EXISTS _electric_oplog (\n  rowid INTEGER PRIMARY KEY AUTOINCREMENT,\n  namespace String NOT NULL,\n  tablename String NOT NULL,\n  optype String NOT NULL,\n  primaryKey String NOT NULL,\n  newRow String,\n  oldRow String,\n  timestamp TEXT\n);\n"

      stripped_1 = ElectricMigrations.Sqlite.strip_comments(str1)

      assert stripped_1 ==
               "\CREATE TABLE IF NOT EXISTS _electric_meta (\n  key TEXT PRIMARY KEY,\n  value BLOB\n);\n"

      stripped_2 = ElectricMigrations.Sqlite.strip_comments(str2)

      assert stripped_2 ==
               "CREATE TABLE IF NOT EXISTS _electric_oplog (\n  rowid INTEGER PRIMARY KEY AUTOINCREMENT,\n  namespace String NOT NULL,\n  tablename String NOT NULL,\n  optype String NOT NULL,\n  primaryKey String NOT NULL,\n  newRow String,\n  oldRow String,\n  timestamp TEXT\n);\n"
    end

    test "sluggifying title" do
      dt = %DateTime{
        year: 1964,
        month: 12,
        day: 5,
        zone_abbr: "UTC",
        hour: 9,
        minute: 30,
        second: 7,
        microsecond: {345_678, 6},
        utc_offset: 0,
        std_offset: 0,
        time_zone: "Etc/UTC"
      }

      title = " Paul's birthday  yay!!!"

      fixed = Migrations.slugify_title(title, dt)

      assert fixed == "19641205_093007_345_paul_s_birthday_yay"
    end

    test "tests trigger has all columns" do
      {:ok, conn} = electric_conn()

      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Triggers.add_triggers_to_last_migration(
          [%{name: "test1", original_body: sql}],
          Migrations.satellite_template()
        )

      :ok = Exqlite.Sqlite3.execute(conn, sql)

      ## adding a red fish
      :ok =
        Exqlite.Sqlite3.execute(
          conn,
          "insert into fish (value, colour) values ('abcdefg', 'red')"
        )

      {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM _electric_oplog;")
      ops = get_while_more(conn, statement, [])

      [_rowid, _namespace, tablename, optype, primaryKey, newRow, oldRow, _timestamp] =
        Enum.at(ops, 0)

      assert tablename == "fish"
      assert optype == "INSERT"
      assert primaryKey == "{\"value\":\"abcdefg\"}"
      assert newRow == "{\"value\":\"abcdefg\",\"colour\":\"red\"}"
      assert oldRow == nil
    end

    test "tests trigger has all columns for multiple migrations" do
      {:ok, conn} = electric_conn()

      sql1 = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      sql2 = """
      ALTER TABLE fish
      ADD COLUMN colour TEXT;
      """

      {sql_out1, _warning} =
        Triggers.add_triggers_to_last_migration(
          [%{name: "test1", original_body: sql1}],
          Migrations.satellite_template()
        )

      migration_1 = %{name: "test1", original_body: sql1}
      migration_2 = %{name: "test2", original_body: sql2}

      {sql_out2, _warning} =
        Triggers.add_triggers_to_last_migration(
          [migration_1, migration_2],
          Migrations.satellite_template()
        )

      :ok = Exqlite.Sqlite3.execute(conn, sql_out1)
      :ok = Exqlite.Sqlite3.execute(conn, sql_out2)

      #        IO.puts(sql_out)

      ## adding a red fish
      :ok =
        Exqlite.Sqlite3.execute(
          conn,
          "insert into fish (value, colour) values ('abcdefg', 'red')"
        )

      {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM _electric_oplog;")
      ops = get_while_more(conn, statement, [])
      #        IO.puts(ops)

      [_rowid, _namespace, tablename, optype, primaryKey, newRow, oldRow, _timestamp] =
        Enum.at(ops, 0)

      assert tablename == "fish"
      assert optype == "INSERT"
      assert primaryKey == "{\"value\":\"abcdefg\"}"
      assert newRow == "{\"value\":\"abcdefg\",\"colour\":\"red\"}"
      assert oldRow == nil
    end
  end

  def get_while(conn, statement, names) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, result} ->
        get_while(conn, statement, result ++ names)

      :done ->
        names
    end
  end

  def get_while_more(conn, statement, results) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, result} -> get_while_more(conn, statement, [result | results])
      :done -> results
    end
  end
end
