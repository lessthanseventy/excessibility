defmodule Excessibility.SystemTest do
  use ExUnit.Case, async: true

  alias Excessibility.System

  describe "open_with_system_cmd/1" do
    test "module implements SystemBehaviour" do
      # Ensure the module is loaded
      {:module, _} = Code.ensure_loaded(System)

      # Verify the module implements the expected behaviour
      behaviours = System.__info__(:attributes)[:behaviour] || []
      assert Excessibility.SystemBehaviour in behaviours
    end

    test "function is defined" do
      # Ensure the module is loaded first
      {:module, _} = Code.ensure_loaded(System)

      # Verify the function exists
      # We don't call it to avoid opening browsers during tests
      assert {:open_with_system_cmd, 1} in System.__info__(:functions)
    end
  end
end
