defmodule MigrationsParseTest do
  use ExUnit.Case

  describe "Parse sql" do
    test "tests can get column names" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      ) STRICT, WITHOUT ROWID;;
      """

      migration = %Electric.Migration{name: "test1", original_body: sql_in}
      {:ok, info} = Electric.Migrations.Parse.sql_ast_from_migration_set([migration])

      column_names = info["main.fish"][:columns]
      assert column_names == ["value", "colour"]
    end

    test "tests nonsense SQL fails" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      );
      SOME BOLLOCKS;
      """

      {:error, [reason]} =
        Electric.Migrations.Parse.sql_ast_from_migration_set([
          %Electric.Migration{name: "test1", original_body: sql_in}
        ])

      assert reason == "In migration test1 SQL error: near \"SOME\": syntax error"
    end

    test "tests can check for strictness and rowid" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY,
      colour TEXT
      );
      """

      {:error, [reason1, reason2]} =
        Electric.Migrations.Parse.sql_ast_from_migration_set([
          %Electric.Migration{name: "test1", original_body: sql_in}
        ])

      assert reason1 ==
               "The table fish is not WITHOUT ROWID. Add the WITHOUT ROWID option at the end of the create table statement and make sure you also specify a primary key"

      assert reason2 ==
               "The table fish is not STRICT. Add the STRICT option at the end of the create table statement"
    end

    test "tests getting SQL structure for templating" do
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

      {:ok, info} =
        Electric.Migrations.Parse.sql_ast_from_migration_set([
          %Electric.Migration{name: "test1", original_body: sql_in}
        ])

      expected_info = %{
        "main.parent" => %{
          :namespace => "main",
          :table_name => "parent",
          :validation_fails => [],
          :primary => ["id"],
          :foreign_keys => [],
          :columns => ["id", "value"],
          column_infos: %{
            0 => %{
              cid: 0,
              dflt_value: nil,
              name: "id",
              notnull: 1,
              pk: 1,
              type: "INTEGER",
              pk_desc: false,
              unique: false
            },
            1 => %{
              cid: 1,
              dflt_value: nil,
              name: "value",
              notnull: 0,
              pk: 0,
              type: "TEXT",
              pk_desc: false,
              unique: false
            }
          },
          foreign_keys_info: [],
          table_info: %{
            name: "parent",
            rootpage: 2,
            sql:
              "CREATE TABLE parent (\n  id INTEGER PRIMARY KEY,\n  value TEXT\n) STRICT, WITHOUT ROWID",
            tbl_name: "parent",
            type: "table"
          }
        },
        "main.child" => %{
          :namespace => "main",
          :table_name => "child",
          :validation_fails => [],
          :primary => ["id"],
          :foreign_keys => [
            %{:child_key => "daddy", :parent_key => "id", :table => "main.parent"}
          ],
          :columns => ["id", "daddy"],
          column_infos: %{
            0 => %{
              cid: 0,
              dflt_value: nil,
              name: "id",
              notnull: 1,
              pk: 1,
              type: "INTEGER",
              pk_desc: false,
              unique: false
            },
            1 => %{
              cid: 1,
              dflt_value: nil,
              name: "daddy",
              notnull: 1,
              pk: 0,
              type: "INTEGER",
              pk_desc: false,
              unique: false
            }
          },
          foreign_keys_info: [
            %{
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
          table_info: %{
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

    test "tests getting uniques" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS parent (
        id INTEGER PRIMARY KEY DESC,
        value TEXT,
        email TEXT UNIQUE
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS child (
        id INTEGER PRIMARY KEY,
        daddy INTEGER NOT NULL,
        FOREIGN KEY(daddy) REFERENCES parent(id)
      ) STRICT, WITHOUT ROWID;
      """

      {:ok, info} =
        Electric.Migrations.Parse.sql_ast_from_migration_set([
          %Electric.Migration{name: "test1", original_body: sql_in}
        ])

      expected_info = %{
        "main.child" => %{
          column_infos: %{
            0 => %{
              cid: 0,
              dflt_value: nil,
              name: "id",
              notnull: 1,
              pk: 1,
              type: "INTEGER",
              unique: false,
              pk_desc: false
            },
            1 => %{
              cid: 1,
              dflt_value: nil,
              name: "daddy",
              notnull: 1,
              pk: 0,
              type: "INTEGER",
              unique: false,
              pk_desc: false
            }
          },
          columns: ["id", "daddy"],
          foreign_keys: [%{child_key: "daddy", parent_key: "id", table: "main.parent"}],
          foreign_keys_info: [
            %{
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
          namespace: "main",
          validation_fails: [],
          primary: ["id"],
          table_info: %{
            name: "child",
            rootpage: 4,
            sql:
              "CREATE TABLE child (\n  id INTEGER PRIMARY KEY,\n  daddy INTEGER NOT NULL,\n  FOREIGN KEY(daddy) REFERENCES parent(id)\n) STRICT, WITHOUT ROWID",
            tbl_name: "child",
            type: "table"
          },
          table_name: "child"
        },
        "main.parent" => %{
          column_infos: %{
            0 => %{
              cid: 0,
              dflt_value: nil,
              name: "id",
              notnull: 1,
              pk: 1,
              type: "INTEGER",
              unique: false,
              pk_desc: true
            },
            1 => %{
              cid: 1,
              dflt_value: nil,
              name: "value",
              notnull: 0,
              pk: 0,
              type: "TEXT",
              unique: false,
              pk_desc: false
            },
            2 => %{
              cid: 2,
              dflt_value: nil,
              name: "email",
              notnull: 0,
              pk: 0,
              type: "TEXT",
              unique: true,
              pk_desc: false
            }
          },
          columns: ["id", "value", "email"],
          foreign_keys: [],
          validation_fails: [],
          foreign_keys_info: [],
          namespace: "main",
          primary: ["id"],
          table_info: %{
            name: "parent",
            rootpage: 2,
            sql:
              "CREATE TABLE parent (\n  id INTEGER PRIMARY KEY DESC,\n  value TEXT,\n  email TEXT UNIQUE\n) STRICT, WITHOUT ROWID",
            tbl_name: "parent",
            type: "table"
          },
          table_name: "parent"
        }
      }

      assert info == expected_info
    end

    test "tests getting SQL index structure" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS parent (
        id INTEGER PRIMARY KEY,
        value TEXT,
        email TEXT UNIQUE
      ) STRICT, WITHOUT ROWID;

      CREATE TABLE IF NOT EXISTS child (
        id INTEGER PRIMARY KEY,
        daddy INTEGER NOT NULL,
        FOREIGN KEY(daddy) REFERENCES parent(id)
      ) STRICT, WITHOUT ROWID;
      """

      index_info = Electric.Migrations.Parse.all_index_info([sql_in])

      assert index_info == %{
               "main.parent" => %{
                 0 => %{
                   columns: [
                     %{cid: 0, coll: "BINARY", desc: 0, key: 1, name: "id", seqno: 0},
                     %{cid: 1, coll: "BINARY", desc: 0, key: 0, name: "value", seqno: 1},
                     %{cid: 2, coll: "BINARY", desc: 0, key: 0, name: "email", seqno: 2}
                   ],
                   name: "sqlite_autoindex_parent_2",
                   origin: "pk",
                   partial: 0,
                   seq: 0,
                   unique: 1
                 },
                 1 => %{
                   columns: [
                     %{cid: 2, coll: "BINARY", desc: 0, key: 1, name: "email", seqno: 0},
                     %{cid: 0, coll: "BINARY", desc: 0, key: 0, name: "id", seqno: 1}
                   ],
                   name: "sqlite_autoindex_parent_1",
                   origin: "u",
                   partial: 0,
                   seq: 1,
                   unique: 1
                 }
               }
             }
    end

    test "tests getting SQL conflict" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS parent (
        id INTEGER PRIMARY KEY,
        value TEXT,
        email TEXT UNIQUE ON CONFLICT ROLLBACK
      );

      CREATE TABLE IF NOT EXISTS child (
        id INTEGER PRIMARY KEY,
        daddy INTEGER NOT NULL,
        FOREIGN KEY(daddy) REFERENCES parent(id)
      );
      """

      index_info = Electric.Migrations.Parse.all_index_info([sql_in])

      assert index_info == %{
               "main.parent" => %{
                 0 => %{
                   columns: [
                     %{cid: 2, coll: "BINARY", desc: 0, key: 1, name: "email", seqno: 0},
                     %{cid: -1, coll: "BINARY", desc: 0, key: 0, name: nil, seqno: 1}
                   ],
                   name: "sqlite_autoindex_parent_1",
                   origin: "u",
                   partial: 0,
                   seq: 0,
                   unique: 1
                 }
               }
             }
    end
  end
end
