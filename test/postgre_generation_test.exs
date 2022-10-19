defmodule PostgreGenerationTest do
  use ExUnit.Case

  describe "Generate PostgreSQL SQL text" do
    test "Test create a new table" do
      sql = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      migration = %Electric.Migration{name: "test1", original_body: sql}

      {:ok, postgres_version, _} = Electric.Postgre.Generation.postgre_for_migrations([migration])

      expected = "\nCREATE TABLE main.fish (\n  value text PRIMARY KEY);\n"

      assert expected == postgres_version
    end

    test "Test two migrations and remove not null" do
      sql1 = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;;
      """

      sql2 = """
      CREATE TABLE IF NOT EXISTS goat (
      name TEXT PRIMARY KEY NOT NULL
      ) STRICT, WITHOUT ROWID;
      """

      migration_1 = %Electric.Migration{name: "test_1", original_body: sql1}
      migration_2 = %Electric.Migration{name: "test_2", original_body: sql2}

      {:ok, postgres_version, _} =
        Electric.Postgre.Generation.postgre_for_migrations([migration_1, migration_2])

      expected = "\nCREATE TABLE main.goat (\n  name text PRIMARY KEY);\n"

      assert expected == postgres_version
    end

    test "Test add col" do
      sql1 = """
      CREATE TABLE IF NOT EXISTS fish (
      value TEXT PRIMARY KEY
      ) STRICT, WITHOUT ROWID;
      """

      sql2 = """
      CREATE TABLE IF NOT EXISTS goat (
      name TEXT PRIMARY KEY NOT NULL
      ) STRICT, WITHOUT ROWID;
      ALTER TABLE fish ADD COLUMN eyes INTEGER DEFAULT 2;
      """

      migration_1 = %Electric.Migration{name: "test_1", original_body: sql1}
      migration_2 = %Electric.Migration{name: "test_2", original_body: sql2}

      {:ok, postgres_version, _} =
        Electric.Postgre.Generation.postgre_for_migrations([migration_1, migration_2])

      expected = """
      ALTER TABLE main.fish ADD COLUMN eyes integer DEFAULT 2;

      CREATE TABLE main.goat (
        name text PRIMARY KEY);
      """

      assert expected == postgres_version
    end

    test "foreign keys" do
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

      migration = %Electric.Migration{name: "test1", original_body: sql_in}

      {:ok, postgres_version, _} = Electric.Postgre.Generation.postgre_for_migrations([migration])

      expected = """

      CREATE TABLE main.child (
        id integer PRIMARY KEY,
        daddy integer NOT NULL,
        FOREIGN KEY(daddy) REFERENCES parent(id) MATCH SIMPLE);

      CREATE TABLE main.parent (
        id integer PRIMARY KEY,
        value text);
      """

      assert expected == postgres_version
    end

    test "unique keys" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS parent (
        id INTEGER PRIMARY KEY,
        value TEXT UNIQUE
      ) STRICT, WITHOUT ROWID;

      """

      migration = %Electric.Migration{name: "test1", original_body: sql_in}

      {:ok, postgres_version, _} = Electric.Postgre.Generation.postgre_for_migrations([migration])

      expected = """

      CREATE TABLE main.parent (
        id integer PRIMARY KEY,
        value text UNIQUE);
      """

      assert expected == postgres_version
    end

    test "desc primary keys" do
      sql_in = """
      CREATE TABLE IF NOT EXISTS parent (
        id INTEGER PRIMARY KEY DESC,
        value TEXT UNIQUE
      ) STRICT, WITHOUT ROWID;

      """

      migration = %Electric.Migration{name: "test1", original_body: sql_in}

      {:ok, postgres_version, _} = Electric.Postgre.Generation.postgre_for_migrations([migration])

      expected = """

      CREATE TABLE main.parent (
        id integer PRIMARY KEY DESC,
        value text UNIQUE);
      """

      assert expected == postgres_version
    end
  end
end
