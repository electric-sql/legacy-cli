defmodule ElectricCli.CommandCase do
  @moduledoc """
  This module defines the setup for command tests.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import ExUnit.CaptureIO, only: [capture_io: 1, with_io: 1]

      import ElectricCli.CommandFixtures
      import ElectricCli.CommandHelpers
      import ElectricCli.ConfigCommandHelpers

      @moduletag :tmp_dir
    end
  end

  setup(%{tmp_dir: dir}) do
    start_link_supervised!(ElectricCli.MockServer.spec())

    cwd = File.cwd!()
    File.cd!(dir)

    Memoize.invalidate()

    System.put_env("ELECTRIC_STATE_HOME", Path.join(dir, ".electric_credentials"))

    on_exit(fn ->
      File.cd!(cwd)
      File.rm_rf!(dir)

      System.delete_env("ELECTRIC_STATE_HOME")
    end)

    :ok
  end
end
