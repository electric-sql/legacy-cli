defmodule Electric.Migrations do
  @moduledoc """
  The `Migrations` context.

  Munges sql migrations and uploads them to the server

  """

  @trigger_template """

CREATE TABLE IF NOT EXISTS _oplog (
  tablename String NOT NULL,
  optype String NOT NULL,
  oprowid String NOT NULL,
  newrow String,
  oldrow String,
  timestamp INTEGER
);

DROP TRIGGER IF EXISTS insert_<table_name>_into_oplog;
CREATE TRIGGER insert_<table_name>_into_oplog
   AFTER INSERT ON <table_name>
BEGIN
  INSERT INTO _oplog (tablename, optype, oprowid, newrow, oldrow, timestamp)
VALUES
  ('<table_name>','INSERT', new.rowid, json_object('value', new.value), NULL, NULL);
END;

DROP TRIGGER IF EXISTS update_<table_name>_into_oplog;
CREATE TRIGGER update_<table_name>_into_oplog
   AFTER UPDATE ON <table_name>
BEGIN
  INSERT INTO _oplog (tablename, optype, oprowid, newrow, oldrow, timestamp)
VALUES
  ('<table_name>','UPDATE', new.rowid, json_object('value', new.value), json_object('value', old.value), NULL);
END;

DROP TRIGGER IF EXISTS delete_<table_name>_into_oplog;
CREATE TRIGGER delete_<table_name>_into_oplog
   AFTER DELETE ON <table_name>
BEGIN
  INSERT INTO _oplog (tablename, optype, oprowid, newrow, oldrow, timestamp)
VALUES
    ('<table_name>','DELETE', new.rowid, NULL, json_object('value', old.value), NULL);
END;
"""

  def get_template() do
    @trigger_template
  end

  @doc """
Takes a folder which contains sql migration files and adds the SQLite triggers for any newly created tables
"""
  def deploy_migrations(migrations_folder) do
    sql_file_paths = add_triggers_to_folder(migrations_folder, @trigger_template)
    send_migrations_to_api(sql_file_paths)
  end

 # ---------- below are private functions but defp is useless for unit testing!
 # "don't test the internals of your module only the external interface" ?!?!?!?

  def send_migrations_to_api(sql_file_paths) do
    throw :NotImplemented
  end

  def add_triggers_to_folder(path, template) do
    sql_file_paths = Path.wildcard(path <> "/*.sql")
    Enum.each(sql_file_paths, fn path -> add_triggers_to_file(path, template) end)
    sql_file_paths
  end


  def add_triggers_to_file(path, template) do
    if String.slice(path, -3..-1) == "sql" do
      case File.read(path) do
        {:ok, sql} ->
          with_triggers = add_triggers_to_sql(sql, template)
          if sql != with_triggers do
            File.write(path, with_triggers)
          end
        {:error, _reason} ->
          IO.puts("unable to read sql file " <> path)
      end
    end
  end


  def add_triggers_to_sql(sql_in, template) do
    # adds triggers for any newly created tables to the end of the sql
    new_table_names = created_table_names(sql_in)

    if length(new_table_names) == 0 do
      # no op if no tables created
      sql_in
    else
      # add line return
      fixed_sql = ensure_line_return(sql_in)
      # only add triggers not already there
      triggers = for table_name <- new_table_names do
        trigger = trigger_templated(table_name, template)
        if String.contains?(fixed_sql, trigger) do
          nil
        else
          trigger
        end
      end

      new_triggers = for trigger when trigger != nil <- triggers do
        trigger
      end

      all_triggers = Enum.join(new_triggers, "\n")
      ensure_line_return(fixed_sql <> all_triggers)
    end
  end


  defp ensure_line_return(str) do
    if String.at(str, -1) != "\n" do
      str <> "\n"
    else
      str
    end
  end


  def trigger_templated(table_name, template) do
    String.replace(template, "<table_name>", table_name)
  end


  def created_table_names(sql_in) do
    # finds the names of any new tables created in the sql
    regex = ~r/CREATE TABLE (?:IF NOT EXISTS )?(.*?) \((?:(?:[^;]|\n)*);/
    matches = Regex.scan(regex, sql_in)
    for m <- matches do
      Enum.at(m, 1)
    end
  end

end
