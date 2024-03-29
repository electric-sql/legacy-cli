defmodule ElectricMigrations.Sqlite.ParseTest do
  use ExUnit.Case
  alias ElectricMigrations.Sqlite.Parse
  alias ElectricMigrations.Ast.ColumnInfo
  alias ElectricMigrations.Ast.ForeignKeyInfo
  alias ElectricMigrations.Ast.FullTableInfo
  alias ElectricMigrations.Ast.TableInfo
  alias ElectricMigrations.Ast.IndexInfo
  alias ElectricMigrations.Ast.IndexColumn

  describe "namespaced_table_names/2" do
    test "finds all tables in SQL which include a database name" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS main.fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      )STRICT, WITHOUT ROWID;

      CREATE TABLE  goat
      (
      value TEXT PRIMARY KEY,
      colour TEXT
      )STRICT, WITHOUT ROWID;

      create table  apples.house
      (
      value TEXT PRIMARY KEY,
      colour TEXT
      )STRICT, WITHOUT ROWID;

      """

      names = Parse.namespaced_table_names(sql_in)

      assert names == ["main.fish", "apples.house"]
    end
  end

  describe "sql_ast_from_migrations/1" do
    test "parsing column names out of migrations" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;
      """

      migration = %{name: "test1", original_body: sql_in}
      {:ok, info, _} = Parse.sql_ast_from_migrations([migration])

      column_names = info["main.fish"].columns
      assert column_names == ["value", "colour"]
    end

    test "fails to parse nonsense SQL" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      );
      SOME BOLLOCKS;
      """

      migration = %{name: "test1", original_body: sql_in}

      {_status, reason} = Parse.sql_ast_from_migrations([migration])
      assert reason == ["In migration test1 SQL error: near \"SOME\": syntax error"]
    end

    test "validates sql for `WITHOUT ROWID` and NOT NULL primary keys" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      );
      """

      {:error, message} =
        Parse.sql_ast_from_migrations([
          %{name: "test1", original_body: sql_in}
        ])

      expected = [
        "The table fish is not WITHOUT ROWID.",
        "The primary key value in table fish must be NOT NULL. Please add NOT NULL to this column."
      ]

      assert message == expected
    end

    test "doesn't allow main namespace" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS main.fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      )STRICT, WITHOUT ROWID;
      """

      {:error, errors} =
        Parse.sql_ast_from_migrations([
          %{name: "test1", original_body: sql_in}
        ])

      assert "In migration test1: The table main.fish has a database name. Please leave this out and only give the table name." in errors
    end

    test "doesn't allow any namespaces" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS apple.fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      )STRICT, WITHOUT ROWID;
      """

      {:error, errors} =
        Parse.sql_ast_from_migrations([
          %{name: "test1", original_body: sql_in}
        ])

      assert "In migration test1: The table apple.fish has a database name. Please leave this out and only give the table name." in errors
    end

    test "doesn't allow uppercase in column names" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
      Value TEXT PRIMARY KEY,
      colour TEXT
      )STRICT, WITHOUT ROWID;
      """

      {:error, message} =
        Parse.sql_ast_from_migrations([
          %{name: "test1", original_body: sql_in}
        ])

      expected = [
        "The name of column Value in table fish is not allowed. Please only use lowercase for column names."
      ]

      assert message == expected
    end

    test "parses sql with foreign key references" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS parent (
        id INTEGER PRIMARY KEY,
        value TEXT
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS child (
        id INTEGER PRIMARY KEY,
        daddy INTEGER NOT NULL,
        FOREIGN KEY(daddy) REFERENCES parent(id)
      ) STRICT, WITHOUT ROWID;
      """

      {:ok, info, _} =
        Parse.sql_ast_from_migrations([
          %{name: "test1", original_body: sql_in}
        ])

      expected_info = %{
        "main.parent" => %FullTableInfo{
          namespace: "main",
          table_name: "parent",
          validation_fails: [],
          warning_messages: [],
          primary: ["id"],
          foreign_keys: [],
          columns: ["id", "value"],
          column_infos: %{
            0 => %ColumnInfo{
              cid: 0,
              dflt_value: nil,
              name: "id",
              notnull: true,
              pk: 1,
              type: "INTEGER",
              pk_desc: false,
              unique: false
            },
            1 => %ColumnInfo{
              cid: 1,
              dflt_value: nil,
              name: "value",
              notnull: false,
              pk: 0,
              type: "TEXT",
              pk_desc: false,
              unique: false
            }
          },
          indices: [
            %IndexInfo{
              seq: 0,
              name: "sqlite_autoindex_parent_1",
              unique?: true,
              origin: :primary_key,
              partial?: false,
              columns: [
                %IndexColumn{
                  rank: 0,
                  column_name: "id",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: true
                },
                %IndexColumn{
                  rank: 1,
                  column_name: "value",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: false
                }
              ]
            }
          ],
          foreign_keys_info: [],
          table_info: %TableInfo{
            name: "parent",
            rootpage: 2,
            sql:
              "CREATE TABLE parent (\n  id INTEGER PRIMARY KEY,\n  value TEXT\n) STRICT, WITHOUT ROWID",
            tbl_name: "parent",
            type: "table"
          }
        },
        "main.child" => %FullTableInfo{
          namespace: "main",
          table_name: "child",
          validation_fails: [],
          warning_messages: [],
          primary: ["id"],
          foreign_keys: [
            %{child_key: "daddy", parent_key: "id", table: "main.parent"}
          ],
          indices: [
            %IndexInfo{
              seq: 0,
              name: "sqlite_autoindex_child_1",
              unique?: true,
              origin: :primary_key,
              partial?: false,
              columns: [
                %IndexColumn{
                  rank: 0,
                  column_name: "id",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: true
                },
                %IndexColumn{
                  rank: 1,
                  column_name: "daddy",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: false
                }
              ]
            }
          ],
          columns: ["id", "daddy"],
          column_infos: %{
            0 => %ColumnInfo{
              cid: 0,
              dflt_value: nil,
              name: "id",
              notnull: true,
              pk: 1,
              type: "INTEGER",
              pk_desc: false,
              unique: false
            },
            1 => %ColumnInfo{
              cid: 1,
              dflt_value: nil,
              name: "daddy",
              notnull: true,
              pk: 0,
              type: "INTEGER",
              pk_desc: false,
              unique: false
            }
          },
          foreign_keys_info: [
            %ForeignKeyInfo{
              from: "daddy",
              id: 0,
              match: "NONE",
              on_delete: "NO ACTION",
              on_update: "NO ACTION",
              seq: 0,
              table: "parent",
              to: "id"
            }
          ],
          table_info: %TableInfo{
            name: "child",
            rootpage: 3,
            sql:
              "CREATE TABLE child (\n  id INTEGER PRIMARY KEY,\n  daddy INTEGER NOT NULL,\n  FOREIGN KEY(daddy) REFERENCES parent(id)\n) STRICT, WITHOUT ROWID",
            tbl_name: "child",
            type: "table"
          }
        }
      }

      assert info == expected_info
    end

    @tag skip: "FIXME: UNIQUE constraints are currently not supported outside of primary keys"
    test "extracts uniqueness info" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS parent (
        id INTEGER PRIMARY KEY DESC,
        value TEXT,
        email TEXT UNIQUE
      ) STRICT, WITHOUT ROWID;
      """

      {:ok, info, _} =
        Parse.sql_ast_from_migrations([
          %{name: "test1", original_body: sql_in}
        ])

      expected_info = %{
        "main.parent" => %FullTableInfo{
          column_infos: %{
            0 => %ColumnInfo{
              cid: 0,
              dflt_value: nil,
              name: "id",
              notnull: true,
              pk: 1,
              type: "INTEGER",
              unique: false,
              pk_desc: true
            },
            1 => %ColumnInfo{
              cid: 1,
              dflt_value: nil,
              name: "value",
              notnull: false,
              pk: 0,
              type: "TEXT",
              unique: false,
              pk_desc: false
            },
            2 => %ColumnInfo{
              cid: 2,
              dflt_value: nil,
              name: "email",
              notnull: false,
              pk: 0,
              type: "TEXT",
              unique: true,
              pk_desc: false
            }
          },
          columns: ["id", "value", "email"],
          foreign_keys: [],
          validation_fails: [],
          warning_messages: [],
          foreign_keys_info: [],
          namespace: "main",
          primary: ["id"],
          table_info: %TableInfo{
            name: "parent",
            rootpage: 2,
            sql:
              "CREATE TABLE parent (\n  id INTEGER PRIMARY KEY DESC,\n  value TEXT,\n  email TEXT UNIQUE\n) STRICT, WITHOUT ROWID",
            tbl_name: "parent",
            type: "table"
          },
          table_name: "parent",
          indices: [
            %IndexInfo{
              seq: 0,
              name: "sqlite_autoindex_parent_2",
              unique?: true,
              origin: :unique_constraint,
              partial?: false,
              columns: [
                %IndexColumn{
                  rank: 0,
                  column_name: "email",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: true
                },
                %IndexColumn{
                  rank: 1,
                  column_name: "id",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: false
                }
              ]
            },
            %IndexInfo{
              seq: 1,
              name: "sqlite_autoindex_parent_1",
              unique?: true,
              origin: :primary_key,
              partial?: false,
              columns: [
                %IndexColumn{
                  rank: 0,
                  column_name: "id",
                  direction: :desc,
                  collating_sequence: "BINARY",
                  key?: true
                },
                %IndexColumn{
                  rank: 1,
                  column_name: "value",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: false
                },
                %IndexColumn{
                  rank: 2,
                  column_name: "email",
                  direction: :asc,
                  collating_sequence: "BINARY",
                  key?: false
                }
              ]
            }
          ]
        }
      }

      assert info == expected_info
    end

    @tag present_because:
           "FIXME: UNIQUE constraints are currently not supported outside of primary keys"
    test "fails on unique constraint columns" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
        id1 TEXT PRIMARY KEY NOT NULL,
        id2 TEXT UNIQUE
      ) WITHOUT ROWID;
      """

      migration = %{name: "test1", original_body: sql_in}
      {:error, errors} = Parse.sql_ast_from_migrations([migration])

      assert ~s|Column "id2" in table "fish" cannot have a UNIQUE constraint. UNIQUE constraints are currently not supported outside of primary keys.| in errors
    end

    @tag skip: "FIXME: composite primary keys are not currently supported, see next test"
    test "supports composite primary keys" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
        id1 TEXT NOT NULL,
        id2 TEXT NOT NULL,
        PRIMARY KEY (id1, id2)
      ) WITHOUT ROWID;
      """

      migration = %{name: "test1", original_body: sql_in}
      {:ok, ast, nil} = Parse.sql_ast_from_migrations([migration])

      assert %{0 => %{pk: 1}, 1 => %{pk: 2}} = ast["main.fish"].column_infos
      assert ["id1", "id2"] == ast["main.fish"].primary
    end

    @tag skip: "FIXME: composite primary keys are not currently supported, see next test"
    test "all parts of a composite primary key should be non-nullable" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
        id1 TEXT NOT NULL,
        id2 TEXT,
        PRIMARY KEY (id1, id2)
      ) WITHOUT ROWID;
      """

      migration = %{name: "test1", original_body: sql_in}
      {:error, errors} = Parse.sql_ast_from_migrations([migration])

      assert "The primary key value in table fish must be NOT NULL. Please add NOT NULL to this column." in errors
    end

    @tag present_because:
           "FIXME: composite primary keys are not currently supported, see next test"
    test "fails when composite primary key is present" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
        id1 TEXT NOT NULL,
        id2 TEXT NOT NULL,
        PRIMARY KEY (id1, id2)
      ) WITHOUT ROWID;
      """

      migration = %{name: "test1", original_body: sql_in}
      {:error, reasons} = Parse.sql_ast_from_migrations([migration])

      assert ~s|Table "fish": composite primary keys are not currently supported| in reasons
    end

    # This test actually passes if validation is removed, but since PG generation has to be support this as well, we have the validation
    @tag skip: "WIP: explicit indices are not currently supported"
    test "extra indices are allowed" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
        id INTEGER PRIMARY KEY,
        value TEXT
      ) STRICT, WITHOUT ROWID;
      CREATE INDEX indexed_values ON fish (value);
      """

      migration = %{name: "test1", original_body: sql_in}
      {:ok, ast, nil} = Parse.sql_ast_from_migrations([migration])

      assert [%{name: "indexed_values", origin: :create_index}, _] = ast["main.fish"].indices
    end

    @tag present_because: "WIP: explicit indices are not currently supported"
    test "fails when extra explicit indices are present" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
        id INTEGER PRIMARY KEY,
        value TEXT
      ) STRICT, WITHOUT ROWID;
      CREATE INDEX indexed_values ON fish (value);
      """

      migration = %{name: "test1", original_body: sql_in}
      {:error, reasons} = Parse.sql_ast_from_migrations([migration])

      assert ~s|Can't create index "indexed_values" on table "fish": explicit indices are not currently supported| in reasons
    end

    @tag present_because:
           "Only backwards-compatible migrations (CREATE TABLE and ADD COLUMN) are supported for now"
    test "fails when non-ADD COLUMN alter statements are present" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
        id INTEGER PRIMARY KEY,
        value TEXT
      ) STRICT, WITHOUT ROWID;
      ALTER TABLE fish ADD COLUMN test TEXT;
      ALTER TABLE fish RENAME COLUMN test TO test2;
      ALTER TABLE fish DROP COLUMN test2;
      ALTER TABLE fish RENAME TO fish2;
      """

      migration = %{name: "test1", original_body: sql_in}
      {:error, reasons} = Parse.sql_ast_from_migrations([migration])

      assert "In migration test1: Altering table fish to RENAME COLUMN is considered a non-backwards compatible migration. Only backwards-compatible migrations (CREATE TABLE and ADD COLUMN) are supported for now" in reasons

      assert "In migration test1: Altering table fish to DROP COLUMN is considered a non-backwards compatible migration. Only backwards-compatible migrations (CREATE TABLE and ADD COLUMN) are supported for now" in reasons

      assert "In migration test1: Altering table fish to RENAME TO is considered a non-backwards compatible migration. Only backwards-compatible migrations (CREATE TABLE and ADD COLUMN) are supported for now" in reasons
    end
  end
end
