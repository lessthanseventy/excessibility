defmodule Excessibility.BrowserBehaviour do
  @callback page_source(Wallaby.Session.t()) :: String.t()
end
