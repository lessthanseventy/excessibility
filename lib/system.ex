defmodule Excessibility.System do
  @moduledoc """
  Default implementation for system commands.

  Opens files in the system's default browser. This is used during interactive
  diff resolution to show `.good.html` and `.bad.html` files side by side.

  ## Mocking for CI

  In CI environments, you typically want to mock this module to avoid
  opening browsers:

      # test/test_helper.exs
      Mox.defmock(Excessibility.SystemMock, for: Excessibility.SystemBehaviour)
      Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)

      # In tests
      stub(Excessibility.SystemMock, :open_with_system_cmd, fn _path -> :ok end)
  """
  @behaviour Excessibility.SystemBehaviour

  @doc """
  Opens a file in the system's default browser.

  Uses platform-appropriate commands:
  - macOS: `open`
  - Linux: `xdg-open`
  - Windows: `start`
  """
  @impl true
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
