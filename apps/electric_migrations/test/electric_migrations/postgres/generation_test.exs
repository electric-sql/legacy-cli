defmodule ElectricMigrations.Postgres.GenerationTest do
  use ExUnit.Case, async: true

  alias ElectricMigrations.Postgres.Generation

  test "handling of CREATE TABLE statements" do
    sql = """
    CREATE TABLE IF NOT EXISTS fish (
    value TEXT PRIMARY KEY
    ) STRICT, WITHOUT ROWID;
    """

    migration = %{name: "test1", original_body: sql}

    {:ok, postgres_version, _} = Generation.postgres_sql_for_last_migration([migration])

    expected = """

    CREATE TABLE public.fish (
      value text PRIMARY KEY);
    ALTER TABLE public.fish REPLICA IDENTITY FULL;
    """

    assert expected == postgres_version
  end

  test "handling of multiple tables and removal of tables with nullable primary key" do
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

    migration_1 = %{name: "test_1", original_body: sql1}
    migration_2 = %{name: "test_2", original_body: sql2}

    {:ok, postgres_version, _} =
      Generation.postgres_sql_for_last_migration([migration_1, migration_2])

    expected = """

    CREATE TABLE public.goat (
      name text PRIMARY KEY);
    ALTER TABLE public.goat REPLICA IDENTITY FULL;
    """

    assert expected == postgres_version
  end

  test "handling of ALTER TABLE statements to add columns" do
    sql1 = """
    CREATE TABLE IF NOT EXISTS fish (
    value TEXT PRIMARY KEY NOT NULL
    ) STRICT, WITHOUT ROWID;
    """

    sql2 = """
    CREATE TABLE IF NOT EXISTS goat (
    name TEXT PRIMARY KEY NOT NULL
    ) STRICT, WITHOUT ROWID;
    ALTER TABLE fish ADD COLUMN eyes INTEGER DEFAULT 2;
    """

    migration_1 = %{name: "test_1", original_body: sql1}
    migration_2 = %{name: "test_2", original_body: sql2}

    {:ok, postgres_version, _} =
      Generation.postgres_sql_for_last_migration([migration_1, migration_2])

    expected = """

    CREATE TABLE public.goat (
      name text PRIMARY KEY);
    ALTER TABLE public.goat REPLICA IDENTITY FULL;
    ALTER TABLE public.fish ADD COLUMN eyes bigint DEFAULT 2;
    """

    assert expected == postgres_version
  end

  @tag skip: "FIXME: column drops are handled incorrectly"
  test "handling of ALTER TABLE drop columns in the middle of the table" do
    sql1 = """
    CREATE TABLE IF NOT EXISTS table1 (
      first_column TEXT PRIMARY KEY NOT NULL,
      second_column TEXT NOT NULL,
      third_column INTEGER NOT NULL
    ) STRICT, WITHOUT ROWID;
    """

    sql2 = """
    ALTER TABLE table1 DROP COLUMN second_column;
    """

    migration_1 = %{name: "test_1", original_body: sql1}
    migration_2 = %{name: "test_2", original_body: sql2}

    {:ok, postgres_version, _} =
      Generation.postgres_sql_for_last_migration([migration_1, migration_2])

    expected = """
    ALTER TABLE public.test DROP COLUMN second_column;
    """

    assert String.trim(expected) == String.trim(postgres_version)
  end

  @tag skip: "FIXME: column drops are handled incorrectly"
  test "handling of ALTER TABLE dropping and adding a column in the same migration" do
    sql1 = """
    CREATE TABLE IF NOT EXISTS table1 (
      first_column TEXT PRIMARY KEY NOT NULL,
      second_column TEXT NOT NULL
    ) STRICT, WITHOUT ROWID;
    """

    sql2 = """
    ALTER TABLE table1 DROP COLUMN second_column;
    ALTER TABLE table1 ADD COLUMN third_column INTEGER NOT NULL;
    """

    migration_1 = %{name: "test_1", original_body: sql1}
    migration_2 = %{name: "test_2", original_body: sql2}

    {:ok, postgres_version, _} =
      Generation.postgres_sql_for_last_migration([migration_1, migration_2])

    expected = """
    ALTER TABLE public.test DROP COLUMN second_column;
    ALTER TABLE table1 ADD COLUMN third_column INTEGER NOT NULL;
    """

    assert String.trim(expected) == String.trim(postgres_version)
  end

  test "handling of foreign keys" do
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

    migration = %{name: "test1", original_body: sql_in}

    {:ok, postgres_version, _} = Generation.postgres_sql_for_last_migration([migration])

    expected = """

    CREATE TABLE public.parent (
      id bigint PRIMARY KEY,
      value text);
    ALTER TABLE public.parent REPLICA IDENTITY FULL;

    CREATE TABLE public.child (
      id bigint PRIMARY KEY,
      daddy bigint NOT NULL,
      FOREIGN KEY(daddy) REFERENCES parent(id) MATCH SIMPLE);
    ALTER TABLE public.child REPLICA IDENTITY FULL;
    """

    assert expected == postgres_version
  end

  @tag skip: "FIXME: UNIQUE constraints are currently not supported outside of primary keys"
  test "handling of unique keys" do
    sql_in = """
    CREATE TABLE IF NOT EXISTS parent (
      id INTEGER PRIMARY KEY,
      value TEXT UNIQUE
    ) STRICT, WITHOUT ROWID;

    """

    migration = %{name: "test1", original_body: sql_in}

    {:ok, postgres_version, _} = Generation.postgres_sql_for_last_migration([migration])

    expected = """

    CREATE TABLE public.parent (
      id bigint PRIMARY KEY,
      value text UNIQUE);
    ALTER TABLE public.parent REPLICA IDENTITY FULL;
    """

    assert expected == postgres_version
  end

  @tag skip: "FIXME: explicit indices are not currently supported"
  test "handling of explicit indices" do
    sql_in = """
    CREATE TABLE IF NOT EXISTS parent (
      id INTEGER PRIMARY KEY,
      value TEXT
    ) STRICT, WITHOUT ROWID;
    CREATE INDEX indexed_values ON parent (value);
    """

    migration = %{name: "test1", original_body: sql_in}

    {:ok, postgres_version, _} = Generation.postgres_sql_for_last_migration([migration])

    expected = """

    CREATE TABLE public.parent (
      id bigint PRIMARY KEY,
      value text);
    CREATE INDEX indexed_values ON public.parent (value);
    ALTER TABLE public.parent REPLICA IDENTITY FULL;
    """

    assert expected == postgres_version
  end

  test "handling of ordering on primary keys" do
    sql_in = """
    CREATE TABLE IF NOT EXISTS parent (
      id INTEGER PRIMARY KEY DESC,
      value TEXT
    ) STRICT, WITHOUT ROWID;

    """

    migration = %{name: "test1", original_body: sql_in}

    {:ok, postgres_version, _} = Generation.postgres_sql_for_last_migration([migration])

    expected = """

    CREATE TABLE public.parent (
      id bigint PRIMARY KEY DESC,
      value text);
    ALTER TABLE public.parent REPLICA IDENTITY FULL;
    """

    assert expected == postgres_version
  end

  @tag skip: "FIXME: composite primary keys are not currently supported"
  test "handling of composite primary keys" do
    sql = """
    CREATE TABLE IF NOT EXISTS fish (
      id1 TEXT NOT NULL,
      id2 TEXT NOT NULL,
      PRIMARY KEY (id1, id2)
    ) WITHOUT ROWID;
    """

    migration = %{name: "test1", original_body: sql}

    {:ok, postgres_version, _} = Generation.postgres_sql_for_last_migration([migration])

    expected = """

    CREATE TABLE public.fish (
      id1 text,
      id2 text,
      PRIMARY KEY (id1, id2));
    ALTER TABLE public.fish REPLICA IDENTITY FULL;
    """

    assert expected == postgres_version
  end
end
