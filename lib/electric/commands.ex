defmodule Electric.Commands do
  @moduledoc """
  Default imports for a command.
  """

  def command do
    quote do
      import Electric.Flags

      alias Electric.Client
      alias Electric.Password
      alias Electric.Session
      alias Electric.Util
    end
  end
end
