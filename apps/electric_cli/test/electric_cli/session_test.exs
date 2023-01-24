defmodule ElectricCli.SessionTest do
  use ExUnit.Case, async: false

  alias ElectricCli.Session

  defmacrop with_env(vars, do: block) do
    save_vars =
      quote do
        env = Map.new(unquote(vars), fn {k, _} -> {k, System.get_env(k)} end)
      end

    set_vars =
      for {k, v} <- vars do
        quote do
          System.put_env(unquote(k), unquote(v))
        end
      end

    reset_vars =
      quote do
        for {k, v} <- env do
          case v do
            nil ->
              System.delete_env(k)

            v ->
              System.put_env(k, v)
          end
        end
      end

    quote do
      unquote(save_vars)

      try do
        unquote(set_vars)
        unquote(block)
      after
        unquote(reset_vars)
      end
    end
  end

  describe "state_path/0" do
    test "should default to ~/.local/state/electric" do
      assert Session.state_path() ==
               Path.join([System.user_home(), ".local", "state", "electric"])
    end

    @tag :tmp_dir
    test "should use $HOME if set", ctx do
      with_env([{"HOME", ctx.tmp_dir}]) do
        assert Session.state_path() == Path.join([ctx.tmp_dir, ".local", "state", "electric"])
      end
    end

    @tag :tmp_dir
    test "should use $XDG_STATE_HOME as root if set", ctx do
      with_env([{"XDG_STATE_HOME", ctx.tmp_dir}]) do
        assert Session.state_path() == Path.join(ctx.tmp_dir, "electric")
      end
    end

    @tag :tmp_dir
    test "should use $ELECTRIC_STATE_HOME if set", ctx do
      with_env([{"ELECTRIC_STATE_HOME", ctx.tmp_dir}]) do
        assert Session.state_path() == ctx.tmp_dir
      end
    end

    @tag :tmp_dir
    test "should raise if $ELECTRIC_STATE_HOME is a file", ctx do
      path = Path.join(ctx.tmp_dir, "electric")
      File.write!(path, "oh dear")

      with_env([{"ELECTRIC_STATE_HOME", path}]) do
        assert_raise(RuntimeError, fn -> Session.state_path() end)
      end
    end
  end
end
