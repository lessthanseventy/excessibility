defmodule Excessibility.TelemetryCapture.ProfilesTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Profiles

  describe "get/1" do
    test "returns analyzers for :quick profile" do
      analyzers = Profiles.get(:quick)

      assert is_list(analyzers)
      assert length(analyzers) <= 3
    end

    test "returns analyzers for :memory profile" do
      analyzers = Profiles.get(:memory)

      assert :memory in analyzers
      assert :data_growth in analyzers
    end

    test "returns analyzers for :performance profile" do
      analyzers = Profiles.get(:performance)

      assert :performance in analyzers
      assert :event_pattern in analyzers
    end

    test "returns analyzers for :full profile" do
      analyzers = Profiles.get(:full)

      # Full should include all default-enabled analyzers
      assert length(analyzers) >= 5
    end

    test "returns nil for unknown profile" do
      assert Profiles.get(:nonexistent) == nil
    end
  end

  describe "list/0" do
    test "returns all available profile names" do
      profiles = Profiles.list()

      assert :quick in profiles
      assert :memory in profiles
      assert :performance in profiles
      assert :full in profiles
    end
  end
end
