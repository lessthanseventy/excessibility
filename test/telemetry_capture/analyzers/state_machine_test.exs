defmodule Excessibility.TelemetryCapture.Analyzers.StateMachineTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.StateMachine

  describe "name/0" do
    test "returns :state_machine" do
      assert StateMachine.name() == :state_machine
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert StateMachine.default_enabled?() == true
    end
  end

  describe "requires_enrichers/0" do
    test "declares state enricher dependency" do
      assert StateMachine.requires_enrichers() == [:state]
    end
  end

  describe "analyze/2" do
    test "returns map with findings and stats" do
      timeline = %{timeline: []}

      result = StateMachine.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
      assert is_list(result.findings)
      assert is_map(result.stats)
    end

    test "detects no issues with stable state" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:user_id, :products]},
          %{sequence: 2, event: "handle_event", state_keys: [:user_id, :products]},
          %{sequence: 3, event: "handle_event", state_keys: [:user_id, :products]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      assert result.findings == []
    end

    test "detects keys added between events" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:user_id]},
          %{sequence: 2, event: "handle_event", state_keys: [:user_id, :products, :cart]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      assert length(result.findings) == 1
      finding = List.first(result.findings)
      assert finding.severity == :info
      assert finding.message =~ "2 keys added"
      assert finding.message =~ "events 1→2"
      assert :products in finding.metadata.added
      assert :cart in finding.metadata.added
    end

    test "detects keys removed between events" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:user_id, :products, :cart]},
          %{sequence: 2, event: "handle_event", state_keys: [:user_id]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      assert length(result.findings) == 1
      finding = List.first(result.findings)
      assert finding.severity == :info
      assert finding.message =~ "2 keys removed"
      assert finding.message =~ "events 1→2"
      assert :products in finding.metadata.removed
      assert :cart in finding.metadata.removed
    end

    test "detects keys both added and removed" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:user_id, :old_data]},
          %{sequence: 2, event: "handle_event", state_keys: [:user_id, :new_data, :settings]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      assert length(result.findings) == 1
      finding = List.first(result.findings)
      assert finding.severity == :info
      assert finding.message =~ "2 keys added, 1 keys removed"
      assert :new_data in finding.metadata.added
      assert :settings in finding.metadata.added
      assert :old_data in finding.metadata.removed
    end

    test "detects rapid state changes (many transitions)" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:a]},
          %{sequence: 2, event: "handle_event", state_keys: [:a, :b]},
          %{sequence: 3, event: "handle_event", state_keys: [:a, :b, :c]},
          %{sequence: 4, event: "handle_event", state_keys: [:a, :b, :c, :d]},
          %{sequence: 5, event: "handle_event", state_keys: [:a, :b, :c, :d, :e]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      # Should have findings for each transition (4 transitions)
      assert length(result.findings) >= 4

      # Check for rapid change warning
      rapid_change_finding? =
        Enum.any?(result.findings, fn f ->
          f.severity == :warning and f.message =~ "Rapid state changes detected"
        end)

      assert rapid_change_finding?
    end

    test "detects unstable state (keys added then removed)" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:user_id]},
          %{sequence: 2, event: "handle_event", state_keys: [:user_id, :temp_data]},
          %{sequence: 3, event: "handle_event", state_keys: [:user_id]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      unstable_finding? =
        Enum.any?(result.findings, fn f ->
          f.severity == :warning and f.message =~ "Unstable state detected"
        end)

      assert unstable_finding?
    end

    test "calculates transition statistics" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:a]},
          %{sequence: 2, event: "handle_event", state_keys: [:a, :b]},
          %{sequence: 3, event: "handle_event", state_keys: [:a, :b, :c]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      assert result.stats.total_transitions == 2
      assert result.stats.total_keys_added == 2
      assert result.stats.total_keys_removed == 0
    end

    test "handles empty timeline" do
      timeline = %{timeline: []}

      result = StateMachine.analyze(timeline, [])

      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles single event timeline" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", state_keys: [:user_id]}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      assert result.findings == []
      assert result.stats.total_transitions == 0
    end

    test "handles timeline without state enrichment data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event"}
        ]
      }

      result = StateMachine.analyze(timeline, [])

      # Should not crash, treat as no state data
      assert result.findings == []
    end
  end
end
