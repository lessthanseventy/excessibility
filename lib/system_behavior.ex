defmodule Excessibility.SystemBehaviour do
  @moduledoc """
  Behaviour for system-level operations.

  This behaviour defines the interface for opening files in the system browser,
  used during interactive diff resolution.

  ## Mocking

  Implement this behaviour to mock system operations in tests:

      Mox.defmock(Excessibility.SystemMock, for: Excessibility.SystemBehaviour)
      Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)

  See `Excessibility.System` for the default implementation.
  """

  @doc """
  Opens a file path in the system's default browser.

  ## Parameters

  - `path` - The file path to open

  ## Returns

  The result of the system command (typically ignored).
  """
  @callback open_with_system_cmd(String.t()) :: any()
end
