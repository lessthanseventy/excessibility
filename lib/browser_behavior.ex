defmodule Excessibility.BrowserBehaviour do
  @moduledoc """
  Behaviour for browser page source extraction.

  This behaviour defines the interface for extracting HTML from Wallaby
  browser sessions.

  ## Mocking

  Implement this behaviour to mock browser operations in tests:

      Mox.defmock(Excessibility.BrowserMock, for: Excessibility.BrowserBehaviour)
      Application.put_env(:excessibility, :browser_mod, Excessibility.BrowserMock)

  The default implementation uses `Wallaby.Browser.page_source/1`.
  """

  @doc """
  Extracts the page source HTML from a Wallaby session.

  ## Parameters

  - `session` - A `Wallaby.Session` struct

  ## Returns

  The page HTML as a string.
  """
  @callback page_source(Wallaby.Session.t()) :: String.t()
end
