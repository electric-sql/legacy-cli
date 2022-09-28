defmodule MigrationsTest do
  use ExUnit.Case

  @trigger_template EEx.compile_string(
                      "<%= original_sql %><%= for {table_full_name, _table} <- tables do %>--ADD A TRIGGER FOR <%= table_full_name %>;<% end %>\n"
                    )

  describe "Migration validation" do
    test "tests valid SQL passes" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      migration = %Electric.Migration{name: "test1", original_body: sql}

      assert Electric.Migration.ensure_original_body(migration).error == nil
    end
  end

  describe "adds_triggers to sql" do
    test "add a trigger" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      expected = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      --ADD A TRIGGER FOR main.fish;
      """

      assert Electric.Migrations.Triggers.add_triggers_to_last_migration(
               [%Electric.Migration{name: "test1", original_body: sql}],
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

      sql =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%Electric.Migration{name: "test1", original_body: sql}],
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
        key TEXT,
        value TEXT
      );

      --initialisation of the metadata table
      INSERT INTO _electric_meta(key,value) VALUES ('currRowId', '-1'), ('ackRowId','-1'), ('compensations', 0);


      -- These are toggles for turning the triggers on and off
      DROP TABLE IF EXISTS trigger_settings;
      CREATE TABLE trigger_settings(tablename STRING PRIMARY KEY, flag INTEGER);
      INSERT INTO trigger_settings(tablename,flag) VALUES ('main.cats', 1);
      INSERT INTO trigger_settings(tablename,flag) VALUES ('main.fish', 1);


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
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.cats')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'cats', 'INSERT', json_object('id', new.id), json_object('id', new.id, 'name', new.name, 'favourite', new.favourite), NULL, NULL);
      END;

      DROP TRIGGER IF EXISTS update_main_cats_into_oplog;
      CREATE TRIGGER update_main_cats_into_oplog
         AFTER UPDATE ON main.cats
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.cats')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'cats', 'UPDATE', json_object('id', new.id), json_object('id', new.id, 'name', new.name, 'favourite', new.favourite), json_object('id', old.id, 'name', old.name, 'favourite', old.favourite), NULL);
      END;

      DROP TRIGGER IF EXISTS delete_main_cats_into_oplog;
      CREATE TRIGGER delete_main_cats_into_oplog
         AFTER DELETE ON main.cats
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.cats')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'cats', 'DELETE', json_object('id', old.id), NULL, json_object('id', old.id, 'name', old.name, 'favourite', old.favourite), NULL);
      END;

      -- Triggers for foreign key compensations

      DROP TRIGGER IF EXISTS compensation_insert_main_cats_favourite_into_oplog;
      CREATE TRIGGER compensation_insert_main_cats_favourite_into_oplog
         AFTER INSERT ON main.cats
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish') AND
              1 == (SELECT value from _electric_meta WHERE key == 'compensations')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        SELECT 'main', 'fish', 'UPDATE', json_object('id', id, 'colour', colour), json_object('id', id, 'colour', colour), NULL, NULL
        FROM main.fish WHERE id = new.favourite;
      END;

      DROP TRIGGER IF EXISTS compensation_update_main_cats_favourite_into_oplog;
      CREATE TRIGGER compensation_update_main_cats_favourite_into_oplog
         AFTER UPDATE ON main.cats
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish') AND
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
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'fish', 'INSERT', json_object('id', new.id, 'colour', new.colour), json_object('id', new.id, 'colour', new.colour), NULL, NULL);
      END;

      DROP TRIGGER IF EXISTS update_main_fish_into_oplog;
      CREATE TRIGGER update_main_fish_into_oplog
         AFTER UPDATE ON main.fish
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish')
      BEGIN
        INSERT INTO _electric_oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
        VALUES ('main', 'fish', 'UPDATE', json_object('id', new.id, 'colour', new.colour), json_object('id', new.id, 'colour', new.colour), json_object('id', old.id, 'colour', old.colour), NULL);
      END;

      DROP TRIGGER IF EXISTS delete_main_fish_into_oplog;
      CREATE TRIGGER delete_main_fish_into_oplog
         AFTER DELETE ON main.fish
         WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish')
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

      sql =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%Electric.Migration{name: "test1", original_body: sql}],
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
                 "fish",
                 "sqlite_sequence",
                 "trigger_settings"
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

      sql =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%Electric.Migration{name: "test1", original_body: sql}],
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

    test "tests trigger has all columns" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      sql =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%Electric.Migration{name: "test1", original_body: sql}],
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
      #        IO.puts(ops)

      #        [table_name, op, row_id, new_value, old_value, _timestamp] = Enum.at(ops, 0)
      #
      #        assert table_name == "fish"
      #        assert op == "INSERT"
      #        assert row_id == 1
      #        assert new_value == "{\"value\":\"abcdefg\",\"colour\":\"red\"}"
      #        assert old_value == nil

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

      sql_out1 =
        Electric.Migrations.Triggers.add_triggers_to_last_migration(
          [%Electric.Migration{name: "test1", original_body: sql1}],
          Electric.Migrations.get_template()
        )

      migration_1 = %Electric.Migration{name: "test1", original_body: sql1}
      migration_2 = %Electric.Migration{name: "test2", original_body: sql2}

      sql_out2 =
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

  @trigger_template EEx.compile_string(
                      "<%= original_sql %><%= for {table_full_name, _table} <- tables do %>\n--ADD A TRIGGER FOR <%= table_full_name %>;\n<% end %>"
                    )

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
      migrations_path = Path.join([temp, "migrations"])
      {:success, _msg} = Electric.Migrations.init_migrations(%{:dir => temp})
      assert File.exists?(migrations_path)
    end

    test "init and then modify and then build" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])
      {:success, _msg} = Electric.Migrations.init_migrations(%{:dir => temp})
      assert File.exists?(migrations_path)

      sql_file_paths = Path.join([migrations_path, "*", "migration.sql"]) |> Path.wildcard()
      my_new_migration = List.first(sql_file_paths)
      migration_folder = Path.dirname(my_new_migration)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])

      {:success, _msg} =
        Electric.Migrations.build_migrations(%{}, %{:migrations => migrations_path})

      assert File.exists?(Path.join([migration_folder, "satellite.sql"]))
    end

    def init_and_add_migration(temp) do
      migrations_path = Path.join([temp, "migrations"])
      {:success, _msg} = Electric.Migrations.init_migrations(%{:dir => temp})

      my_new_migration = most_recent_migration_file(migrations_path)

      new_content = """
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(my_new_migration, new_content, [:append])
      Process.sleep(1000)

      {:success, _msg} =
        Electric.Migrations.new_migration("another", %{:migrations => migrations_path})

      cats_content = """
      CREATE TABLE IF NOT EXISTS cats (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      second_migration = most_recent_migration_file(migrations_path)
      File.write!(second_migration, cats_content, [:append])
    end

    def most_recent_migration_file(migrations_path) do
      Path.join([migrations_path, "*", "migration.sql"]) |> Path.wildcard() |> List.last()
    end

    test "init and then modify and then add and then build" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])
      init_and_add_migration(temp)
      second_migration_folder = Path.dirname(most_recent_migration_file(migrations_path))

      {:success, _msg} =
        Electric.Migrations.build_migrations(%{}, %{:migrations => migrations_path})

      assert File.exists?(Path.join([second_migration_folder, "satellite.sql"]))
    end

    test "test can build with manifest" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])
      init_and_add_migration(temp)

      {:success, _msg} =
        Electric.Migrations.build_migrations(%{:manifest => true}, %{
          :migrations => migrations_path
        })

      assert File.exists?(Path.join([migrations_path, "manifest.json"]))
    end

    test "test can build with json bundle" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])
      init_and_add_migration(temp)

      {:success, _msg} =
        Electric.Migrations.build_migrations(%{:bundle => true}, %{:migrations => migrations_path})

      assert File.exists?(Path.join([migrations_path, "index.js"]))
    end

    test "test can build with js bundle" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])
      init_and_add_migration(temp)

      {:success, _msg} =
        Electric.Migrations.build_migrations(%{:bundle => true}, %{:migrations => migrations_path})

      assert File.exists?(Path.join([migrations_path, "index.js"]))
    end

    test "test build warning" do
      temp = temp_folder()
      migrations_path = Path.join([temp, "migrations"])
      init_and_add_migration(temp)

      {:success, _msg} =
        Electric.Migrations.build_migrations(%{}, %{:migrations => migrations_path})

      migration = most_recent_migration_file(migrations_path)

      dogs_content = """
      CREATE TABLE IF NOT EXISTS dogs (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      File.write!(migration, dogs_content, [:append])

      {:success, _msg} =
        Electric.Migrations.build_migrations(%{}, %{:migrations => migrations_path})
    end
  end

  describe "adds_triggers to sql files" do
    test "add a trigger to a sql file" do
      path = "test/support/migration.sql"

      ts = System.os_time(:second)
      migration_name = "#{ts}_test_migration"

      temp = temp_folder()

      migration_folder = Path.join([temp, "migrations", migration_name])
      migration_file_path = "#{migration_folder}/migration.sql"
      File.mkdir_p!(migration_folder)
      File.copy(path, migration_file_path)

      dst_file_path = Path.join([migration_folder, "satellite.sql"])

      {:ok, migration} = File.read(migration_file_path)

      m = %Electric.Migration{
        name: migration_name,
        original_body: migration,
        src_folder: Path.join([temp, "migrations"])
      }

      Electric.Migrations.add_triggers_to_migration(
        [m],
        @trigger_template
      )

      expected = """
      /*
      ElectricDB Migration
      {"metadata": {"name": "#{migration_name}", "sha256": "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775"}}
      */
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      --ADD A TRIGGER FOR main.items;
      """

      modified = File.read!(dst_file_path)
      assert modified == expected
    end

    test "add a trigger to all sql files in a folder" do
      path = "test/support/migration.sql"

      ts = System.os_time(:second)
      migration_name = "#{ts}_test_migration"
      temp = temp_folder()
      migrations_folder = Path.join([temp, "migrations"])
      migration_folder = Path.join([migrations_folder, migration_name])
      migration_file_path = "#{migration_folder}/migration.sql"
      File.mkdir_p!(migration_folder)
      File.copy(path, migration_file_path)

      dst_file_path = Path.join([migration_folder, "satellite.sql"])

      Electric.Migrations.build_migrations(
        %{},
        %{
          :migrations => migrations_folder,
          :template => @trigger_template
        }
      )

      expected = """
      /*
      ElectricDB Migration
      {"metadata": {"name": "#{migration_name}", "sha256": "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775"}}
      */
      CREATE TABLE IF NOT EXISTS items (
        value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      --ADD A TRIGGER FOR main.items;
      """

      modified = File.read!(dst_file_path)
      #      IO.puts modified
      assert modified == expected
    end

    test "creates a manifest" do
      path = "test/support/migration.sql"
      path_2 = "test/support/migration2.sql"

      ts = System.os_time(:second)
      ts2 = ts + 100
      migration_name = "#{ts}_test_migration"
      migration_name_2 = "#{ts2}_test_migration"
      temp = temp_folder()
      migrations_folder = Path.join([temp, "migrations"])

      migration_folder = Path.join([migrations_folder, migration_name])
      migration_folder_2 = Path.join([migrations_folder, migration_name_2])
      migration_file_path = "#{migration_folder}/migration.sql"
      migration_file_path_2 = "#{migration_folder_2}/migration.sql"
      File.mkdir_p!(migration_folder)
      File.mkdir_p!(migration_folder_2)
      File.copy(path, migration_file_path)
      File.copy(path_2, migration_file_path_2)

      manifest_path = Path.join([migrations_folder, "manifest.json"])

      Electric.Migrations.build_migrations(
        %{},
        %{
          :migrations => migrations_folder
        }
      )

      Electric.Migrations.write_manifest(migrations_folder)
      manifest = Jason.decode!(File.read!(manifest_path))

      expected = %{
        "migrations" => [
          %{
            "name" => migration_name,
            "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775"
          },
          %{
            "name" => migration_name_2,
            "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3"
          }
        ]
      }

      assert manifest == expected
    end

    test "creates a bundle" do
      path = "test/support/migration.sql"
      path_2 = "test/support/migration2.sql"

      ts = System.os_time(:second)
      ts2 = ts + 100
      migration_name = "#{ts}_test_migration"
      migration_name_2 = "#{ts2}_test_migration"
      temp = temp_folder()
      migrations_folder = Path.join([temp, "migrations"])

      migration_folder = Path.join([migrations_folder, migration_name])
      migration_folder_2 = Path.join([migrations_folder, migration_name_2])
      migration_file_path = "#{migration_folder}/migration.sql"
      migration_file_path_2 = "#{migration_folder_2}/migration.sql"
      File.mkdir_p!(migration_folder)
      File.mkdir_p!(migration_folder_2)
      File.copy(path, migration_file_path)
      File.copy(path_2, migration_file_path_2)

      File.mkdir_p!(migration_folder)
      File.mkdir_p!(migration_folder_2)
      File.copy(path, migration_file_path)
      File.copy(path_2, migration_file_path_2)

      bundle_path = Path.join([migrations_folder, "manifest.bundle.json"])

      Electric.Migrations.build_migrations(
        %{},
        %{
          :migrations => migrations_folder,
          :template => @trigger_template
        }
      )

      Electric.Migrations.write_bundle(migrations_folder)

      bundle = Jason.decode!(File.read!(bundle_path))
      #      IO.inspect(bundle)

      expected = %{
        "migrations" => [
          %{
            "body" =>
              "/*\nElectricDB Migration\n{\"metadata\": {\"name\": \"#{migration_name}\", \"sha256\": \"211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775\"}}\n*/\nCREATE TABLE IF NOT EXISTS items (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;\n--ADD A TRIGGER FOR main.items;\n",
            "name" => migration_name,
            "encoding" => "escaped",
            "sha256" => "211b1e2b203d1fcac6ccb526d2775ec1f5575d4018ab1a33272948ce0ae76775"
          },
          %{
            "body" =>
              "/*\nElectricDB Migration\n{\"metadata\": {\"name\": \"#{migration_name_2}\", \"sha256\": \"946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3\"}}\n*/\nCREATE TABLE IF NOT EXISTS cat (\n  value TEXT PRIMARY KEY\n) STRICT, WITHOUT ROWID;\n--ADD A TRIGGER FOR main.cat;\n\n--ADD A TRIGGER FOR main.items;\n",
            "name" => migration_name_2,
            "encoding" => "escaped",
            "sha256" => "946f0f3a0d0338fa486d3d7da35c3b6032f837336fb9a08f933d44675bb264d3"
          }
        ]
      }

      assert bundle == expected
    end

    test "creates a js bundle" do
      path = "test/support/migration.sql"
      path_2 = "test/support/migration2.sql"

      ts = System.os_time(:second)
      ts2 = ts + 100
      migration_name = "#{ts}_test_migration"
      migration_name_2 = "#{ts2}_test_migration"
      temp = temp_folder()
      migrations_folder = Path.join([temp, "migrations"])

      migration_folder = Path.join([migrations_folder, migration_name])
      migration_folder_2 = Path.join([migrations_folder, migration_name_2])
      migration_file_path = "#{migration_folder}/migration.sql"
      migration_file_path_2 = "#{migration_folder_2}/migration.sql"
      File.mkdir_p!(migration_folder)
      File.mkdir_p!(migration_folder_2)
      File.copy(path, migration_file_path)
      File.copy(path_2, migration_file_path_2)

      File.mkdir_p!(migration_folder)
      File.mkdir_p!(migration_folder_2)
      File.copy(path, migration_file_path)
      File.copy(path_2, migration_file_path_2)

      bundle_path = Path.join([migrations_folder, "index.js"])

      _result =
        Electric.Migrations.build_migrations(
          %{},
          %{
            :migrations => migrations_folder,
            :template => @trigger_template
          }
        )

      #      IO.puts("wtf")
      #      IO.inspect(result)
      Electric.Migrations.write_js_bundle(migrations_folder)

      #      bundle = File.read!(bundle_path)
      #      IO.inspect(bundle)

      assert File.exists?(bundle_path)
    end
  end
end
