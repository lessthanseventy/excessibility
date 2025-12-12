defmodule Excessibility.SystemBehaviour do
  @moduledoc false
  @callback open_with_system_cmd(String.t()) :: any()
end
