defmodule Excessibility.BrowserBehaviour do
  @moduledoc false
  @callback page_source(Wallaby.Session.t()) :: String.t()
end
