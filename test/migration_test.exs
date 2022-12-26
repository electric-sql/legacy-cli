defmodule MigrationsTest do
  use ExUnit.Case

  @trigger_template EEx.compile_string(
                      "<%= original_sql %><%= for {table_full_name, _table} <- tables do %>--ADD A TRIGGER FOR <%= table_full_name %>;<% end %>\n"
                    )

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

      assert Electric.Migrations.Triggers.add_triggers_to_last_migration(
               [%{"name" => "test1", "original_body" => sql}],
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

      #      migration = %Electric.Migration{name: "test1", original_body: sql}

      {sql, _warning} =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%{"name" => "test1", "original_body" => sql}],
          Electric.Migrations.get_template()
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
        Electric.Migrations.Triggers.template_all_the_things(
          original_sql,
          tables,
          Electric.Migrations.get_template(),
          true
        )

      expected = """
      Some rubbish

      /*---------------------------------------------
      Below are templated triggers added by Satellite
      ---------------------------------------------*/

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
      INSERT INTO _electric_meta (key, value) VALUES ('compensations', 0), ('lastAckdRowId','0'), ('lastSentRowId', '0'), ('lsn', 'MA=='), ('clientId', '');


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
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%{"name" => "test1", "original_body" => sql}],
          Electric.Migrations.get_template()
        )

      #        IO.inspect(sql)

      {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
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
      sql = """
      CREATE TABLE IF NOT EXISTS main.fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
      :ok = Exqlite.Sqlite3.execute(conn, sql)

      {:ok, statement} =
        Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type='table';")

      names = get_while(conn, statement, [])
      #        IO.inspect(names)
      assert MapSet.new(names) == MapSet.new(["fish"])
    end

    test "tests triggers create op log entries" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%{"name" => "test1", "original_body" => sql}],
          Electric.Migrations.get_template()
        )

      {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
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
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%{"name" => "test1", "original_body" => sql}],
          Electric.Migrations.get_template()
        )

      #      IO.puts(sql)

      commands = Electric.Migrations.Lexer.get_statements(sql)

      {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

      for command <- commands do
        #        IO.puts(command)
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

      stripped = Electric.Migrations.strip_comments(sql)

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

      stripped = Electric.Migrations.strip_comments(sql)

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

      stripped_1 = Electric.Migrations.strip_comments(str1)

      assert stripped_1 ==
               "\CREATE TABLE IF NOT EXISTS _electric_meta (\n  key TEXT PRIMARY KEY,\n  value BLOB\n);\n"

      stripped_2 = Electric.Migrations.strip_comments(str2)

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

      fixed = Electric.Migrations.slugify_title(title, dt)

      assert fixed == "19641205_093007_345_paul_s_birthday_yay"
    end

    test "tests trigger has all columns" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      {sql, _warning} =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%{"name" => "test1", "original_body" => sql}],
          Electric.Migrations.get_template()
        )

      {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
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
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%{"name" => "test1", "original_body" => sql1}],
          Electric.Migrations.get_template()
        )

      migration_1 = %{"name" => "test1", "original_body" => sql1}
      migration_2 = %{"name" => "test2", "original_body" => sql2}

      {sql_out2, _warning} =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [migration_1, migration_2],
          Electric.Migrations.get_template()
        )

      {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
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
        #        IO.inspect(result)
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

defmodule MigrationsFileTest do
  use ExUnit.Case

  #  @trigger_template EEx.compile_string(
  #                      "<%= original_sql %><%= for {table_full_name, _table} <- tables do %>\n--ADD A TRIGGER FOR <%= table_full_name %>;\n<% end %>"
  #                    )

  setup_all do
    tmp_dir = "tmp"
    File.rm_rf(tmp_dir)
    File.mkdir(tmp_dir)
  end

  def temp_folder() do
    Path.join(["tmp", UUID.uuid4()])
  end

  describe "api tests" do
    test "tests can init" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      {:ok, _msg} =
        Electric.Migrations.init_migrations("test_app", %{migrations_dir: migrations_dir})

      assert File.exists?(migrations_dir)
    end

    test "tests init adds migration to manifest" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      {:ok, _msg} =
        Electric.Migrations.init_migrations("test_app", %{migrations_dir: migrations_dir})

      assert File.exists?(migrations_dir)

      init_migration_name =
        most_recent_migration_file(migrations_dir)
        |> Path.dirname()
        |> Path.basename()

      manifest_path = Path.join([migrations_dir, "manifest.json"])
      assert File.exists?(manifest_path)
      manifest = Jason.decode!(File.read!(manifest_path))

      expected = %{
        "app_id" => "test_app",
        "migrations" => [
          %{
            "name" => init_migration_name,
            "sha256" => "01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b",
            "title" => "init",
            "encoding" => "escaped",
            "satellite_body" => []
          }
        ]
      }

      assert manifest == expected
    end

    test "init and then modify and then build updates manifest" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      {:ok, _msg} =
        Electric.Migrations.init_migrations("test_app", %{migrations_dir: migrations_dir})

      assert File.exists?(migrations_dir)

      sql_file_paths = Path.join([migrations_dir, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      migration_folder = Path.dirname(my_new_migration)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:ok, _msg} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: false
        })

      init_migration_name = Path.basename(migration_folder)

      manifest_path = Path.join([migrations_dir, "manifest.json"])
      assert File.exists?(manifest_path)
      manifest = Jason.decode!(File.read!(manifest_path))
      sha = List.first(manifest["migrations"])["sha256"]

      expected = %{
        "app_id" => "test_app",
        "migrations" => [
          %{
            "encoding" => "escaped",
            "name" => init_migration_name,
            "satellite_body" => [
              "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "CREATE TABLE IF NOT EXISTS _electric_oplog (\n  rowid INTEGER PRIMARY KEY AUTOINCREMENT,\n  namespace String NOT NULL,\n  tablename String NOT NULL,\n  optype String NOT NULL,\n  primaryKey String NOT NULL,\n  newRow String,\n  oldRow String,\n  timestamp TEXT\n);",
              "CREATE TABLE IF NOT EXISTS _electric_meta (\n  key TEXT PRIMARY KEY,\n  value BLOB\n);",
              "CREATE TABLE IF NOT EXISTS _electric_migrations (\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\n  name TEXT NOT NULL UNIQUE,\n  sha256 TEXT NOT NULL,\n  applied_at TEXT NOT NULL\n);",
              "INSERT INTO _electric_meta (key, value) VALUES ('compensations', 0), ('lastAckdRowId','0'), ('lastSentRowId', '0'), ('lsn', 'MA=='), ('clientId', '');",
              "DROP TABLE IF EXISTS _electric_trigger_settings;",
              "CREATE TABLE _electric_trigger_settings(tablename STRING PRIMARY KEY, flag INTEGER);",
              "INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.items', 1);",
              "DROP TRIGGER IF EXISTS update_ensure_main_items_primarykey;",
              "CREATE TRIGGER update_ensure_main_items_primarykey\n   BEFORE UPDATE ON main.items\nBEGIN\n  SELECT\n    CASE\n      WHEN old.value != new.value THEN\n        RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')\n    END;\nEND;",
              "DROP TRIGGER IF EXISTS insert_main_items_into_oplog;",
              "CREATE TRIGGER insert_main_items_into_oplog\n   AFTER INSERT ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'INSERT', json_object('value', new.value), json_object('value', new.value), NULL, NULL);\nEND;",
              "DROP TRIGGER IF EXISTS update_main_items_into_oplog;",
              "CREATE TRIGGER update_main_items_into_oplog\n   AFTER UPDATE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'UPDATE', json_object('value', new.value), json_object('value', new.value), json_object('value', old.value), NULL);\nEND;",
              "DROP TRIGGER IF EXISTS delete_main_items_into_oplog;",
              "CREATE TRIGGER delete_main_items_into_oplog\n   AFTER DELETE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value), NULL);\nEND;"
            ],
            "sha256" => sha,
            "title" => "init"
          }
        ]
      }

      assert manifest == expected
    end

    test "init and then modify and then build creates index.js" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      {:ok, _msg} =
        Electric.Migrations.init_migrations("test_app", %{migrations_dir: migrations_dir})

      assert File.exists?(migrations_dir)

      sql_file_paths = Path.join([migrations_dir, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      migration_folder = Path.dirname(my_new_migration)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:ok, _msg} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: false
        })

      init_migration_name = Path.basename(migration_folder)

      js_path = Path.join([migrations_dir, "dist", "index.js"])
      assert File.exists?(js_path)

      local_js = File.read!(js_path)

      expected = """
      export const data = {
        "app_id": "test_app",
        "environment": "local",
        "migrations": [
          {
            "encoding": "escaped",
            "name": "#{init_migration_name}",
            "satellite_body": [
              "CREATE TABLE IF NOT EXISTS items (\\n  value TEXT PRIMARY KEY\\n) STRICT, WITHOUT ROWID;",
              "CREATE TABLE IF NOT EXISTS _electric_oplog (\\n  rowid INTEGER PRIMARY KEY AUTOINCREMENT,\\n  namespace String NOT NULL,\\n  tablename String NOT NULL,\\n  optype String NOT NULL,\\n  primaryKey String NOT NULL,\\n  newRow String,\\n  oldRow String,\\n  timestamp TEXT\\n);",
              "CREATE TABLE IF NOT EXISTS _electric_meta (\\n  key TEXT PRIMARY KEY,\\n  value BLOB\\n);",
              "CREATE TABLE IF NOT EXISTS _electric_migrations (\\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\\n  name TEXT NOT NULL UNIQUE,\\n  sha256 TEXT NOT NULL,\\n  applied_at TEXT NOT NULL\\n);",
              "INSERT INTO _electric_meta (key, value) VALUES ('compensations', 0), ('lastAckdRowId','0'), ('lastSentRowId', '0'), ('lsn', 'MA=='), ('clientId', '');",
              "DROP TABLE IF EXISTS _electric_trigger_settings;",
              "CREATE TABLE _electric_trigger_settings(tablename STRING PRIMARY KEY, flag INTEGER);",
              "INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.items', 1);",
              "DROP TRIGGER IF EXISTS update_ensure_main_items_primarykey;",
              "CREATE TRIGGER update_ensure_main_items_primarykey\\n   BEFORE UPDATE ON main.items\\nBEGIN\\n  SELECT\\n    CASE\\n      WHEN old.value != new.value THEN\\n        RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')\\n    END;\\nEND;",
              "DROP TRIGGER IF EXISTS insert_main_items_into_oplog;",
              "CREATE TRIGGER insert_main_items_into_oplog\\n   AFTER INSERT ON main.items\\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\\nBEGIN\\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\\n  VALUES ('main', 'items', 'INSERT', json_object('value', new.value), json_object('value', new.value), NULL, NULL);\\nEND;",
              "DROP TRIGGER IF EXISTS update_main_items_into_oplog;",
              "CREATE TRIGGER update_main_items_into_oplog\\n   AFTER UPDATE ON main.items\\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\\nBEGIN\\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\\n  VALUES ('main', 'items', 'UPDATE', json_object('value', new.value), json_object('value', new.value), json_object('value', old.value), NULL);\\nEND;",
              "DROP TRIGGER IF EXISTS delete_main_items_into_oplog;",
              "CREATE TRIGGER delete_main_items_into_oplog\\n   AFTER DELETE ON main.items\\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\\nBEGIN\\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\\n  VALUES ('main', 'items', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value), NULL);\\nEND;"
            ],
            "sha256": "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
            "title": "init"
          }
        ]
      }
      """

      assert local_js == expected
    end

    test "init and then change app slug" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      {:ok, _msg} =
        Electric.Migrations.init_migrations("test_app", %{migrations_dir: migrations_dir})

      {:ok, _msg} =
        Electric.Migrations.update_app_id("test_app_changed", %{migrations_dir: migrations_dir})

      init_migration_name =
        most_recent_migration_file(migrations_dir)
        |> Path.dirname()
        |> Path.basename()

      manifest_path = Path.join([migrations_dir, "manifest.json"])
      assert File.exists?(manifest_path)
      manifest = Jason.decode!(File.read!(manifest_path))

      expected = %{
        "app_id" => "test_app_changed",
        "migrations" => [
          %{
            "name" => init_migration_name,
            "sha256" => "01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b",
            "title" => "init",
            "encoding" => "escaped",
            "satellite_body" => []
          }
        ]
      }

      assert manifest == expected
    end

    def change_migrations_name(src_folder, from_name, to_name) do
      from_dir = Path.join([src_folder, from_name])
      to_dir = Path.join([src_folder, to_name])
      File.rename!(from_dir, to_dir)

      manifest_path = Path.join([src_folder, "manifest.json"])
      manifest = Jason.decode!(File.read!(manifest_path))

      migrations = manifest["migrations"]

      updated_migrations =
        for migration <- migrations do
          if migration["name"] == from_name do
            Map.put(migration, "name", to_name)
          else
            migration
          end
        end

      updated = Map.merge(manifest, %{"migrations" => updated_migrations})

      File.write!(manifest_path, Jason.encode!(updated) |> Jason.Formatter.pretty_print())
    end

    def init_and_add_migration(app_id, temp) do
      migrations_dir = Path.join([temp, "migrations"])
      {:ok, _msg} = Electric.Migrations.init_migrations(app_id, %{migrations_dir: migrations_dir})

      my_new_migration = most_recent_migration_file(migrations_dir)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])
      Process.sleep(1000)

      {:ok, _msg} =
        Electric.Migrations.new_migration("another", %{migrations_dir: migrations_dir})

      cats_content = """
      CREATE TABLE IF NOT EXISTS cats (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      second_migration = most_recent_migration_file(migrations_dir)
      File.write!(second_migration, cats_content, [:append])

      [my_new_migration, second_migration]
    end

    def most_recent_migration_file(migrations_dir) do
      Path.join([migrations_dir, "*", "migration.sql"]) |> Path.wildcard() |> List.last()
    end

    test "init and then modify and then add and then build" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test", temp)

      manifest_path = Path.join([migrations_dir, "manifest.json"])
      assert File.exists?(manifest_path)
      #      manifest = Jason.decode!(File.read!(manifest_path))

      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()

      {:ok, _msg} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: false
        })

      manifest = Jason.decode!(File.read!(manifest_path))
      #      sha = List.first(manifest["migrations"])["sha256"]

      expected = %{
        "app_id" => "test",
        "migrations" => [
          %{
            "encoding" => "escaped",
            "name" => first_migration_name,
            "satellite_body" => [
              "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "CREATE TABLE IF NOT EXISTS _electric_oplog (\n  rowid INTEGER PRIMARY KEY AUTOINCREMENT,\n  namespace String NOT NULL,\n  tablename String NOT NULL,\n  optype String NOT NULL,\n  primaryKey String NOT NULL,\n  newRow String,\n  oldRow String,\n  timestamp TEXT\n);",
              "CREATE TABLE IF NOT EXISTS _electric_meta (\n  key TEXT PRIMARY KEY,\n  value BLOB\n);",
              "CREATE TABLE IF NOT EXISTS _electric_migrations (\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\n  name TEXT NOT NULL UNIQUE,\n  sha256 TEXT NOT NULL,\n  applied_at TEXT NOT NULL\n);",
              "INSERT INTO _electric_meta (key, value) VALUES ('compensations', 0), ('lastAckdRowId','0'), ('lastSentRowId', '0'), ('lsn', 'MA=='), ('clientId', '');",
              "DROP TABLE IF EXISTS _electric_trigger_settings;",
              "CREATE TABLE _electric_trigger_settings(tablename STRING PRIMARY KEY, flag INTEGER);",
              "INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.items', 1);",
              "DROP TRIGGER IF EXISTS update_ensure_main_items_primarykey;",
              "CREATE TRIGGER update_ensure_main_items_primarykey\n   BEFORE UPDATE ON main.items\nBEGIN\n  SELECT\n    CASE\n      WHEN old.value != new.value THEN\n        RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')\n    END;\nEND;",
              "DROP TRIGGER IF EXISTS insert_main_items_into_oplog;",
              "CREATE TRIGGER insert_main_items_into_oplog\n   AFTER INSERT ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'INSERT', json_object('value', new.value), json_object('value', new.value), NULL, NULL);\nEND;",
              "DROP TRIGGER IF EXISTS update_main_items_into_oplog;",
              "CREATE TRIGGER update_main_items_into_oplog\n   AFTER UPDATE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'UPDATE', json_object('value', new.value), json_object('value', new.value), json_object('value', old.value), NULL);\nEND;",
              "DROP TRIGGER IF EXISTS delete_main_items_into_oplog;",
              "CREATE TRIGGER delete_main_items_into_oplog\n   AFTER DELETE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value), NULL);\nEND;"
            ],
            "sha256" => "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
            "title" => "init"
          },
          %{
            "encoding" => "escaped",
            "name" => second_migration_name,
            "satellite_body" => [
              "CREATE TABLE IF NOT EXISTS cats (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "DROP TABLE IF EXISTS _electric_trigger_settings;",
              "CREATE TABLE _electric_trigger_settings(tablename STRING PRIMARY KEY, flag INTEGER);",
              "INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.cats', 1);",
              "INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.items', 1);",
              "DROP TRIGGER IF EXISTS update_ensure_main_cats_primarykey;",
              "CREATE TRIGGER update_ensure_main_cats_primarykey\n   BEFORE UPDATE ON main.cats\nBEGIN\n  SELECT\n    CASE\n      WHEN old.value != new.value THEN\n        RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')\n    END;\nEND;",
              "DROP TRIGGER IF EXISTS insert_main_cats_into_oplog;",
              "CREATE TRIGGER insert_main_cats_into_oplog\n   AFTER INSERT ON main.cats\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.cats')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'cats', 'INSERT', json_object('value', new.value), json_object('value', new.value), NULL, NULL);\nEND;",
              "DROP TRIGGER IF EXISTS update_main_cats_into_oplog;",
              "CREATE TRIGGER update_main_cats_into_oplog\n   AFTER UPDATE ON main.cats\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.cats')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'cats', 'UPDATE', json_object('value', new.value), json_object('value', new.value), json_object('value', old.value), NULL);\nEND;",
              "DROP TRIGGER IF EXISTS delete_main_cats_into_oplog;",
              "CREATE TRIGGER delete_main_cats_into_oplog\n   AFTER DELETE ON main.cats\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.cats')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'cats', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value), NULL);\nEND;",
              "DROP TRIGGER IF EXISTS update_ensure_main_items_primarykey;",
              "CREATE TRIGGER update_ensure_main_items_primarykey\n   BEFORE UPDATE ON main.items\nBEGIN\n  SELECT\n    CASE\n      WHEN old.value != new.value THEN\n        RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')\n    END;\nEND;",
              "DROP TRIGGER IF EXISTS insert_main_items_into_oplog;",
              "CREATE TRIGGER insert_main_items_into_oplog\n   AFTER INSERT ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'INSERT', json_object('value', new.value), json_object('value', new.value), NULL, NULL);\nEND;",
              "DROP TRIGGER IF EXISTS update_main_items_into_oplog;",
              "CREATE TRIGGER update_main_items_into_oplog\n   AFTER UPDATE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'UPDATE', json_object('value', new.value), json_object('value', new.value), json_object('value', old.value), NULL);\nEND;",
              "DROP TRIGGER IF EXISTS delete_main_items_into_oplog;",
              "CREATE TRIGGER delete_main_items_into_oplog\n   AFTER DELETE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value), NULL);\nEND;"
            ],
            "sha256" => "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad6",
            "title" => "another"
          }
        ]
      }

      assert manifest == expected
    end

    test "test build warning" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])
      init_and_add_migration("test", temp)

      {:ok, _msg} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: false
        })

      migration = most_recent_migration_file(migrations_dir)

      dogs_content = """
      CREATE TABLE IF NOT EXISTS dogs (
        value TEXT PRIMARY KEY
      );
      """

      File.write!(migration, dogs_content, [:append])

      {:error, msgs} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: false
        })

      [msg2, msg3] = msgs

      assert [msg2, msg3] == [
               "The table dogs is not WITHOUT ROWID.",
               "The primary key value in table dogs isn't NOT NULL. Please add NOT NULL to this column."
             ]
    end

    test "test build writes satellite" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])
      init_and_add_migration("test", temp)

      {:ok, _msg} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: true,
          postgres: false
        })

      migration_dir = most_recent_migration_file(migrations_dir) |> Path.dirname()
      satellite_file_path = Path.join(migration_dir, "satellite.sql")
      assert File.exists?(satellite_file_path)
    end

    test "test build writes postgres" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])
      init_and_add_migration("test", temp)

      {:ok, _msg} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: true
        })

      migration_dir = most_recent_migration_file(migrations_dir) |> Path.dirname()
      satellite_file_path = Path.join(migration_dir, "postgres.sql")
      assert File.exists?(satellite_file_path)
    end

    test "test build type warning" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])
      init_and_add_migration("test", temp)

      {:ok, _msg} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: false
        })

      migration = most_recent_migration_file(migrations_dir)

      dogs_content = """
      CREATE TABLE IF NOT EXISTS dogs (
        value INT PRIMARY KEY
      )STRICT, WITHOUT ROWID;
      """

      File.write!(migration, dogs_content, [:append])

      {:error, msgs} =
        Electric.Migrations.build_migrations(%{migrations_dir: migrations_dir}, %{
          satellite: false,
          postgres: false
        })

      assert msgs == [
               "The type INT for column value in table dogs is not allowed. Please use one of INTEGER, REAL, TEXT, BLOB"
             ]
    end

    test "test can sync" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test", temp)

      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()
      change_migrations_name(migrations_dir, first_migration_name, "first_migration_name")
      change_migrations_name(migrations_dir, second_migration_name, "second_migration_name")

      {:ok, _msg} =
        Electric.Migrations.sync_migrations("default", %{migrations_dir: migrations_dir})

      js_path = Path.join([migrations_dir, "dist", "index.js"])
      assert File.exists?(js_path)

      default_js = File.read!(js_path)

      expected = """
      export const data = {
        "app_id": "test",
        "environment": "default",
        "migrations": [
          {
            "encoding": "escaped",
            "name": "first_migration_name",
            "satellite_body": [
              "something random"
            ],
            "sha256": "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
            "status": "applied",
            "title": "init"
          },
          {
            "encoding": "escaped",
            "name": "second_migration_name",
            "satellite_body": [
              "other stuff"
            ],
            "sha256": "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad6",
            "status": "applied",
            "title": "another"
          }
        ]
      }
      """

      assert default_js == expected
    end

    test "test sync fails if different sha" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test2", temp)

      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()
      change_migrations_name(migrations_dir, first_migration_name, "first_migration_name")
      change_migrations_name(migrations_dir, second_migration_name, "second_migration_name")

      {:error, msg} =
        Electric.Migrations.sync_migrations("default", %{migrations_dir: migrations_dir})

      assert msg == "The migration second_migration_name has been changed locally"
    end

    test "test list" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test", temp)
      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()
      change_migrations_name(migrations_dir, first_migration_name, "first_migration_name")
      change_migrations_name(migrations_dir, second_migration_name, "second_migration_name")

      {:ok, listing, _mismatched} =
        Electric.Migrations.list_migrations(%{migrations_dir: migrations_dir})

      assert listing ==
               "\e[0m\n------ Electric SQL Migrations ------\n\nfirst_migration_name\tdefault: \e[32mapplied\e[0m\nsecond_migration_name\tdefault: \e[32mapplied\e[0m\n"
    end

    test "test list with status" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test", temp)
      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()
      change_migrations_name(migrations_dir, first_migration_name, "first_migration_name")
      change_migrations_name(migrations_dir, second_migration_name, "second_migration_name")

      {:ok, listing, _mismatched} =
        Electric.Migrations.list_migrations(%{migrations_dir: migrations_dir})

      assert listing ==
               "\e[0m\n------ Electric SQL Migrations ------\n\nfirst_migration_name\tdefault: \e[32mapplied\e[0m\nsecond_migration_name\tdefault: \e[32mapplied\e[0m\n"
    end

    test "test lists with error" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test2", temp)
      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()
      change_migrations_name(migrations_dir, first_migration_name, "first_migration_name")
      change_migrations_name(migrations_dir, second_migration_name, "second_migration_name")

      {:ok, listing, mismatched} =
        Electric.Migrations.list_migrations(%{migrations_dir: migrations_dir})

      assert listing ==
               "\e[0m\n------ Electric SQL Migrations ------\n\nfirst_migration_name\tdefault: \e[32mapplied\e[0m\nsecond_migration_name\tdefault: \e[31mdifferent\e[0m\n"

      assert mismatched == [{"second_migration_name", "default"}]
    end

    test "test revert unchanged" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test", temp)
      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()
      change_migrations_name(migrations_dir, first_migration_name, "first_migration_name")
      change_migrations_name(migrations_dir, second_migration_name, "second_migration_name")

      {status, _msg} =
        Electric.Migrations.revert_migration("default", "second_migration_name", %{
          migrations_dir: migrations_dir
        })

      assert status == :error
    end

    test "test revert" do
      temp = temp_folder()
      migrations_dir = Path.join([temp, "migrations"])

      [first_migration, second_migration] = init_and_add_migration("test2", temp)
      first_migration_name = Path.dirname(first_migration) |> Path.basename()
      second_migration_name = Path.dirname(second_migration) |> Path.basename()
      change_migrations_name(migrations_dir, first_migration_name, "first_migration_name")
      change_migrations_name(migrations_dir, second_migration_name, "second_migration_name")

      {status, nil} =
        Electric.Migrations.revert_migration("default", "second_migration_name", %{
          migrations_dir: migrations_dir
        })

      assert status == :ok
      manifest_path = Path.join([migrations_dir, "manifest.json"])
      manifest = Jason.decode!(File.read!(manifest_path))

      expected = %{
        "app_id" => "test2",
        "migrations" => [
          %{
            "encoding" => "escaped",
            "name" => "first_migration_name",
            "satellite_body" => [
              "CREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;",
              "CREATE TABLE IF NOT EXISTS _electric_oplog (\n  rowid INTEGER PRIMARY KEY AUTOINCREMENT,\n  namespace String NOT NULL,\n  tablename String NOT NULL,\n  optype String NOT NULL,\n  primaryKey String NOT NULL,\n  newRow String,\n  oldRow String,\n  timestamp TEXT\n);",
              "CREATE TABLE IF NOT EXISTS _electric_meta (\n  key TEXT PRIMARY KEY,\n  value BLOB\n);",
              "CREATE TABLE IF NOT EXISTS _electric_migrations (\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\n  name TEXT NOT NULL UNIQUE,\n  sha256 TEXT NOT NULL,\n  applied_at TEXT NOT NULL\n);",
              "INSERT INTO _electric_meta (key, value) VALUES ('compensations', 0), ('lastAckdRowId','0'), ('lastSentRowId', '0'), ('lsn', 'MA=='), ('clientId', '');",
              "DROP TABLE IF EXISTS _electric_trigger_settings;",
              "CREATE TABLE _electric_trigger_settings(tablename STRING PRIMARY KEY, flag INTEGER);",
              "INSERT INTO _electric_trigger_settings(tablename,flag) VALUES ('main.items', 1);",
              "DROP TRIGGER IF EXISTS update_ensure_main_items_primarykey;",
              "CREATE TRIGGER update_ensure_main_items_primarykey\n   BEFORE UPDATE ON main.items\nBEGIN\n  SELECT\n    CASE\n      WHEN old.value != new.value THEN\n        RAISE (ABORT,'cannot change the value of column value as it belongs to the primary key')\n    END;\nEND;",
              "DROP TRIGGER IF EXISTS insert_main_items_into_oplog;",
              "CREATE TRIGGER insert_main_items_into_oplog\n   AFTER INSERT ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'INSERT', json_object('value', new.value), json_object('value', new.value), NULL, NULL);\nEND;",
              "DROP TRIGGER IF EXISTS update_main_items_into_oplog;",
              "CREATE TRIGGER update_main_items_into_oplog\n   AFTER UPDATE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'UPDATE', json_object('value', new.value), json_object('value', new.value), json_object('value', old.value), NULL);\nEND;",
              "DROP TRIGGER IF EXISTS delete_main_items_into_oplog;",
              "CREATE TRIGGER delete_main_items_into_oplog\n   AFTER DELETE ON main.items\n   WHEN 1 == (SELECT flag from _electric_trigger_settings WHERE tablename == 'main.items')\nBEGIN\n  INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)\n  VALUES ('main', 'items', 'DELETE', json_object('value', old.value), NULL, json_object('value', old.value), NULL);\nEND;"
            ],
            "sha256" => "2a97d825e41ae70705381016921c55a3b086a813649e4da8fcba040710055747",
            "title" => "init"
          },
          %{
            "encoding" => "escaped",
            "name" => "second_migration_name",
            "satellite_body" => ["-- reverted satellite code"],
            "sha256" => "d0a52f739f137fc80fd67d9fd347cb4097bd6fb182e583f2c64d8de309393ad7",
            "title" => "another"
          }
        ]
      }

      assert manifest == expected

      reverted_migration_path =
        Path.join([migrations_dir, "second_migration_name", "migration.sql"])

      reverted_body = File.read!(reverted_migration_path)

      expected = """
      /*
      Electric SQL Migration
      name: REVERTED VERSION OF THIS FILE
      title": another

      When you build or sync these migrations we will add some triggers and metadata
      so that Electric Satellite can sync your data.

      Write your SQLite migration below.
      */
      CREATE TABLE IF NOT EXISTS cats (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      assert reverted_body == expected
    end
  end
end
