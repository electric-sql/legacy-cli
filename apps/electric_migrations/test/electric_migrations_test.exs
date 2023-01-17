defmodule ElectricMigrationsTest do
  use ExUnit.Case
  doctest ElectricMigrations

  test "greets the world" do
    assert ElectricMigrations.hello() == :world
  end
end
