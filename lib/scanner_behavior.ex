defmodule Excessibility.ScannerBehaviour do
  @moduledoc """
  Behaviour for URL scanning (axe-core analysis and screenshots).

  Implemented by `Excessibility.Scanner`. Can be mocked via the
  `:scanner_mod` config key:

      Application.put_env(:excessibility, :scanner_mod, MyScannerMock)
  """
  @callback scan(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
end
