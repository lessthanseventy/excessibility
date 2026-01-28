defmodule Excessibility.TelemetryCapture.Analyzers.FormValidationTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.FormValidation

  describe "name/0" do
    test "returns :form_validation" do
      assert FormValidation.name() == :form_validation
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert FormValidation.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "no issues with normal validation flow" do
      timeline =
        build_timeline([
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:submit", changeset_valid?: true}
        ])

      result = FormValidation.analyze(timeline, [])

      assert Enum.empty?(result.findings)
    end

    test "detects excessive validations without submit" do
      timeline =
        build_timeline([
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false}
        ])

      result = FormValidation.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &(&1.severity == :warning))
    end

    test "resets count after submit" do
      timeline =
        build_timeline([
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:submit", changeset_valid?: true},
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: false}
        ])

      result = FormValidation.analyze(timeline, [])

      # Only 2 validations after submit, not excessive
      assert Enum.empty?(result.findings)
    end

    test "calculates validation stats" do
      timeline =
        build_timeline([
          %{event: "handle_event:validate", changeset_valid?: false},
          %{event: "handle_event:validate", changeset_valid?: true},
          %{event: "handle_event:submit", changeset_valid?: true}
        ])

      result = FormValidation.analyze(timeline, [])

      assert result.stats.validation_count == 2
      assert result.stats.submit_count == 1
    end

    test "handles empty timeline" do
      result = FormValidation.analyze(%{timeline: []}, [])

      assert result.findings == []
      assert result.stats.validation_count == 0
    end

    test "handles save as submit equivalent" do
      timeline =
        build_timeline([
          %{event: "handle_event:validate"},
          %{event: "handle_event:validate"},
          %{event: "handle_event:save"}
        ])

      result = FormValidation.analyze(timeline, [])

      assert result.stats.submit_count == 1
    end

    test "suggests debouncing for excessive validations" do
      timeline =
        build_timeline([
          %{event: "handle_event:validate"},
          %{event: "handle_event:validate"},
          %{event: "handle_event:validate"},
          %{event: "handle_event:validate"},
          %{event: "handle_event:validate"},
          %{event: "handle_event:validate"},
          %{event: "handle_event:validate"}
        ])

      result = FormValidation.analyze(timeline, [])

      finding = List.first(result.findings)
      assert String.contains?(finding.message, "debounce") or String.contains?(finding.message, "debouncing")
    end
  end

  defp build_timeline(events) do
    entries =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {data, seq} -> Map.put(data, :sequence, seq) end)

    %{timeline: entries}
  end
end
