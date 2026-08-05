defmodule Excessibility.ScannerStub do
  @moduledoc """
  Default `:scanner_mod` for the test suite: reports no violations without
  launching a browser. Tests that assert on axe behavior swap in
  `Excessibility.ScannerMock` (Mox) and restore this stub afterwards.
  """
  @behaviour Excessibility.ScannerBehaviour

  @impl true
  def scan(_url, _opts), do: {:ok, %{violations: []}}
end
