

defmodule MigrationsTest do
  use ExUnit.Case
  @trigger_template EEx.compile_string("<%= original_sql %><%= for {table_full_name, _table} <- tables do %>--ADD A TRIGGER FOR <%= table_full_name %>;<% end %>\n")

    describe "Migration validation" do
      test "tests valid SQL passes" do
        sql = """
              CREATE TABLE IF NOT EXISTS fish (
              value TEXT PRIMARY KEY
              );
              """
        assert Electric.Migrations.validate_sql(sql) == :ok
      end

      test "tests nonsense SQL fails" do
        sql = """
              CREATE TABLE IF NOT EXISTS fish (
              value TEXT PRIMARY KEY
              );
              SOME BOLLOCKS;
              """
        assert Electric.Migrations.validate_sql(sql) == {:error, "near \"SOME\": syntax error"}
      end
    end

  describe "Finds create table instructions in sql" do

    test "find single create" do
      sql = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            """
      assert Electric.Migrations.created_table_names([sql]) == ["main.fish"]
    end

    test "find multiple creates" do
      sql = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            CREATE TABLE IF NOT EXISTS dogs (
            value TEXT PRIMARY KEY
            );
            """

      assert MapSet.new(Electric.Migrations.created_table_names([sql])) == MapSet.new(["main.fish", "main.dogs"])
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
            CREATE TABLE IF NOT EXISTS main.fish (
            value TEXT PRIMARY KEY
            );
            --ADD A TRIGGER FOR main.fish;
            """

      assert Electric.Migrations.add_triggers_to_last_migration([sql], @trigger_template) == expected
    end


    test "adding a trigger is valid sql" do

      sql = """
            CREATE TABLE IF NOT EXISTS fish (
            value TEXT PRIMARY KEY
            );
            """
      sql = Electric.Migrations.add_triggers_to_last_migration([sql], Electric.Migrations.get_template())
      assert Electric.Migrations.validate_sql(sql) == :ok

    end

  end

  describe "Triggers works as expected" do

      test "templating" do

        original_sql = """
        Some rubbish
        """
        tables = %{ "main.fish" => %{:namespace => "main",
          :table_name => "fish",
          :primary => ["id", "colour"],
          :foreign_keys => [],
          :columns => ["id", "colour"]
        },
           "main.cats" => %{:namespace => "main",
            :table_name => "cats",
            :primary => ["id"],
            :foreign_keys => [%{:child_key => "favourite", :parent_key => "id", :table => "main.fish"}],
            :columns => ["id", "name", "favourite"]
          }
       }
        templated = Electric.Migrations.template_all_the_things(original_sql, tables, Electric.Migrations.get_template())
        expected = """
Some rubbish

/*---------------------------------------------
Below are templated triggers added by Satellite
---------------------------------------------*/

-- The ops log table
CREATE TABLE IF NOT EXISTS _oplog (
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
CREATE TABLE IF NOT EXISTS _satellite_meta (
  key TEXT,
  value TEXT
);

--initialisation of the metadata table
INSERT INTO _satellite_meta(key,value) VALUES ('currRowId', '-1'), ('ackRowId','-1'), ('compensations', 0);

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
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
  VALUES ('main', 'cats', 'INSERT', json_object('id', new.id), json_object('id', new.id, 'name', new.name, 'favourite', new.favourite), NULL, NULL);
END;

DROP TRIGGER IF EXISTS update_main_cats_into_oplog;
CREATE TRIGGER update_main_cats_into_oplog
   AFTER UPDATE ON main.cats
   WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.cats')
BEGIN
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
  VALUES ('main', 'cats', 'UPDATE', json_object('id', new.id), json_object('id', new.id, 'name', new.name, 'favourite', new.favourite), json_object('id', old.id, 'name', old.name, 'favourite', old.favourite), NULL);
END;

DROP TRIGGER IF EXISTS delete_main_cats_into_oplog;
CREATE TRIGGER delete_main_cats_into_oplog
   AFTER DELETE ON main.cats
   WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.cats')
BEGIN
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
  VALUES ('main', 'cats', 'DELETE', json_object('id', old.id), NULL, json_object('id', old.id, 'name', old.name, 'favourite', old.favourite), NULL);
END;

-- Triggers for foreign key compensations

DROP TRIGGER IF EXISTS compensation_insert_main_cats_favourite_into_oplog;
CREATE TRIGGER compensation_insert_main_cats_favourite_into_oplog
   AFTER INSERT ON main.cats
   WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish') AND
        1 == (SELECT value from _satellite_meta WHERE key == 'compensations')
BEGIN
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
  SELECT 'main', 'fish', 'UPDATE', json_object('id', id, 'colour', colour), json_object('id', id, 'colour', colour), NULL, NULL
  FROM main.fish WHERE id = new.favourite;
END;

DROP TRIGGER IF EXISTS compensation_update_main_cats_favourite_into_oplog;
CREATE TRIGGER compensation_update_main_cats_favourite_into_oplog
   AFTER UPDATE ON main.cats
   WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish') AND
        1 == (SELECT value from _satellite_meta WHERE key == 'compensations')
BEGIN
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
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
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
  VALUES ('main', 'fish', 'INSERT', json_object('id', new.id, 'colour', new.colour), json_object('id', new.id, 'colour', new.colour), NULL, NULL);
END;

DROP TRIGGER IF EXISTS update_main_fish_into_oplog;
CREATE TRIGGER update_main_fish_into_oplog
   AFTER UPDATE ON main.fish
   WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish')
BEGIN
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
  VALUES ('main', 'fish', 'UPDATE', json_object('id', new.id, 'colour', new.colour), json_object('id', new.id, 'colour', new.colour), json_object('id', old.id, 'colour', old.colour), NULL);
END;

DROP TRIGGER IF EXISTS delete_main_fish_into_oplog;
CREATE TRIGGER delete_main_fish_into_oplog
   AFTER DELETE ON main.fish
   WHEN 1 == (SELECT flag from trigger_settings WHERE tablename == 'main.fish')
BEGIN
  INSERT INTO _oplog (namespace, tablename, optype, primaryKey, newRow, oldRow, timestamp)
  VALUES ('main', 'fish', 'DELETE', json_object('id', old.id, 'colour', old.colour), NULL, json_object('id', old.id, 'colour', old.colour), NULL);
END;\n\n\n
"""
        assert templated == expected


      end


      test "tests op table created" do
        sql = """
              CREATE TABLE IF NOT EXISTS fish (
              value TEXT PRIMARY KEY
              );
              """
        sql = Electric.Migrations.add_triggers_to_last_migration([sql], Electric.Migrations.get_template())

#        IO.inspect(sql)

        {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
        :ok = Exqlite.Sqlite3.execute(conn, sql)
        {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type='table';")
        names = get_while(conn, statement, [])
        assert MapSet.new(names) == MapSet.new(["_oplog", "_satellite_meta", "fish", "sqlite_sequence", "trigger_settings"])

      end



      test "tests using namespaces" do
        sql = """
              CREATE TABLE IF NOT EXISTS main.fish (
              value TEXT PRIMARY KEY
              );
              """

        {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
        :ok = Exqlite.Sqlite3.execute(conn, sql)
        {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type='table';")

        names = get_while(conn, statement, [])
#        IO.inspect(names)
        assert MapSet.new(names) == MapSet.new(["fish"])

      end


      test "tests triggers create op log entries" do
        sql = """
              CREATE TABLE IF NOT EXISTS fish (
              value TEXT PRIMARY KEY
              );
              """
        sql = Electric.Migrations.add_triggers_to_last_migration([sql], Electric.Migrations.get_template())
        {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
        :ok = Exqlite.Sqlite3.execute(conn, sql)

        ## adding a fish
        :ok = Exqlite.Sqlite3.execute(conn, "insert into fish (value) values ('abcdefg')")

        {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM _oplog;")
        ops = get_while_more(conn, statement, [])

        [_rowid, _namespace, tablename, optype, primaryKey, newRow, oldRow, _timestamp] = Enum.at(ops, 0)

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
              );
              """
        sql = Electric.Migrations.add_triggers_to_last_migration([sql], Electric.Migrations.get_template())
        {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
        :ok = Exqlite.Sqlite3.execute(conn, sql)

        ## adding a red fish
        :ok = Exqlite.Sqlite3.execute(conn, "insert into fish (value, colour) values ('abcdefg', 'red')")

        {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM _oplog;")
        ops = get_while_more(conn, statement, [])
#        IO.puts(ops)

#        [table_name, op, row_id, new_value, old_value, _timestamp] = Enum.at(ops, 0)
#
#        assert table_name == "fish"
#        assert op == "INSERT"
#        assert row_id == 1
#        assert new_value == "{\"value\":\"abcdefg\",\"colour\":\"red\"}"
#        assert old_value == nil

        [_rowid, _namespace, tablename, optype, primaryKey, newRow, oldRow, _timestamp] = Enum.at(ops, 0)

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
              );
              """
        sql2 = """
              ALTER TABLE fish
              ADD COLUMN colour TEXT;
              """
        sql_out = Electric.Migrations.add_triggers_to_last_migration([sql1, sql2], Electric.Migrations.get_template())
        {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
        :ok = Exqlite.Sqlite3.execute(conn, sql1)
        :ok = Exqlite.Sqlite3.execute(conn, sql_out)

#        IO.puts(sql_out)

        ## adding a red fish
        :ok = Exqlite.Sqlite3.execute(conn, "insert into fish (value, colour) values ('abcdefg', 'red')")

        {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM _oplog;")
        ops = get_while_more(conn, statement, [])
#        IO.puts(ops)

        [_rowid, _namespace, tablename, optype, primaryKey, newRow, oldRow, _timestamp] = Enum.at(ops, 0)

        assert tablename == "fish"
        assert optype == "INSERT"
        assert primaryKey == "{\"value\":\"abcdefg\"}"
        assert newRow == "{\"value\":\"abcdefg\",\"colour\":\"red\"}"
        assert oldRow == nil
      end


      test "tests can get column names" do
        sql_in = """
              CREATE TABLE IF NOT EXISTS fish (
              value TEXT PRIMARY KEY,
              colour TEXT
              );
              """
        info = Electric.Migrations.all_tables_info([sql_in])

        column_names = info["main.fish"][:columns]
        assert column_names == ["value", "colour"]
      end


      test "tests getting SQL structure for templating" do

        sql_in = """
CREATE TABLE IF NOT EXISTS parent (
  id INTEGER PRIMARY KEY,
  value TEXT
);

CREATE TABLE IF NOT EXISTS child (
  id INTEGER PRIMARY KEY,
  daddy INTEGER NOT NULL,
  FOREIGN KEY(daddy) REFERENCES parent(id)
);
"""
        info = Electric.Migrations.all_tables_info([sql_in])

        expected_info = %{ "main.parent" => %{:namespace => "main",
          :table_name => "parent",
          :primary => ["id"],
          :foreign_keys => [],
          :columns => ["id", "value"]
        },
           "main.child" => %{:namespace => "main",
            :table_name => "child",
            :primary => ["id"],
            :foreign_keys => [%{:child_key => "daddy", :parent_key => "id", :table => "main.parent"}],
            :columns => ["id", "daddy"]
          }
       }
        assert info == expected_info
      end
    end

  def get_while(conn, statement, names) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, result} ->
#        IO.inspect(result)
        get_while(conn, statement, result ++ names)
      :done -> names
    end
  end

  def get_while_more(conn, statement, results) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, result} -> get_while_more(conn, statement,[result | results])
      :done -> results
    end
  end
end


defmodule MigrationsFileTest do
  use ExUnit.Case
  @trigger_template EEx.compile_string("<%= original_sql %><%= for {table_full_name, _table} <- tables do %>\n--ADD A TRIGGER FOR <%= table_full_name %>;\n<% end %>")

  setup_all do
    tmp_dir = "tmp"
    File.rm_rf(tmp_dir)
    File.mkdir(tmp_dir)
  end

  def temp_folder() do
     Path.join(["tmp", UUID.uuid4()])
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

      Electric.Migrations.add_triggers_to_migration_folder(migration_folder, [migration], @trigger_template)

      expected = """
      /*
      ElectricDB Migration
      {"metadata": {"name": "#{migration_name}", "sha256": "dbaef4e408811b090f22375599cc14553b806c61d3d0788a1f36a2bc2c956a20"}}
      */
      CREATE TABLE IF NOT EXISTS main.items (
        value TEXT PRIMARY KEY
      );
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

      Electric.Migrations.add_triggers(migrations_folder, @trigger_template)

      expected = """
      /*
      ElectricDB Migration
      {"metadata": {"name": "#{migration_name}", "sha256": "dbaef4e408811b090f22375599cc14553b806c61d3d0788a1f36a2bc2c956a20"}}
      */
      CREATE TABLE IF NOT EXISTS main.items (
        value TEXT PRIMARY KEY
      );
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

      manifest_path =  Path.join([migrations_folder, "manifest.json"])

      Electric.Migrations.write_manifest(migrations_folder)

      manifest = Jason.decode!(File.read!(manifest_path))

      assert manifest == %{"migrations" => [migration_name, migration_name_2]}
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

      bundle_path =  Path.join([migrations_folder, "manifest.bundle.json"])

      Electric.Migrations.add_triggers(migrations_folder, @trigger_template)
      Electric.Migrations.write_bundle(migrations_folder)

      bundle = Jason.decode!(File.read!(bundle_path))
#      IO.inspect(bundle)

      expected =  %{
         "migrations" => [
           %{
             "body" => "/*\nElectricDB Migration\n{\"metadata\": {\"name\": \"#{migration_name}\", \"sha256\": \"dbaef4e408811b090f22375599cc14553b806c61d3d0788a1f36a2bc2c956a20\"}}\n*/\nCREATE TABLE IF NOT EXISTS main.items (\n  value TEXT PRIMARY KEY\n);\n--ADD A TRIGGER FOR main.items;\n",
             "name" => migration_name
           },
           %{
             "body" => "/*\nElectricDB Migration\n{\"metadata\": {\"name\": \"#{migration_name_2}\", \"sha256\": \"46d68acde8a4fdef52ac0dfa6d4555acece4404b8a79270458fb67267eb645c5\"}}\n*/\nCREATE TABLE IF NOT EXISTS main.cat (\n  value TEXT PRIMARY KEY\n);\n--ADD A TRIGGER FOR main.cat;\n\n--ADD A TRIGGER FOR main.items;\n",
             "name" => migration_name_2
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

      bundle_path =  Path.join([migrations_folder, "manifest.bundle.js"])

      Electric.Migrations.add_triggers(migrations_folder, @trigger_template)
      Electric.Migrations.write_js_bundle(migrations_folder)

#      bundle = File.read!(bundle_path)
#      IO.inspect(bundle)

      assert File.exists?(bundle_path)
    end

  end


end