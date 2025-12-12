defmodule Excessibility.System do
  @moduledoc """
  Opens a file using the default browser across OS types.
  """
  @behaviour Excessibility.SystemBehaviour

  def open_with_system_cmd(path) do
    cmd =
      case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "start"
      end

    System.cmd(cmd, [path])
  end
end
