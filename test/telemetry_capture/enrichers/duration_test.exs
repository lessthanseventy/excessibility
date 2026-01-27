defmodule Excessibility.TelemetryCapture.Enrichers.DurationTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.Duration

  describe "name/0" do
    test "returns :duration" do
      assert Duration.name() == :duration
    end
  end

  describe "enrich/2" do
    test "returns map with duration fields" do
      assigns = %{user_id: 123}
      opts = [measurements: %{duration: 1_500_000}]

      result = Duration.enrich(assigns, opts)

      assert is_map(result)
      assert Map.has_key?(result, :event_duration_ms)
    end

    test "extracts duration from measurements in native units" do
      assigns = %{}
      # Use native time units (convert 2500ms to native)
      duration_native = System.convert_time_unit(2500, :millisecond, :native)
      opts = [measurements: %{duration: duration_native}]

      result = Duration.enrich(assigns, opts)

      assert result.event_duration_ms == 2500
    end

    test "handles small durations in native units" do
      assigns = %{}
      # 5 milliseconds in native units
      duration_native = System.convert_time_unit(5, :millisecond, :native)
      opts = [measurements: %{duration: duration_native}]

      result = Duration.enrich(assigns, opts)

      assert result.event_duration_ms == 5
    end

    test "handles zero duration" do
      assigns = %{}
      opts = [measurements: %{duration: 0}]

      result = Duration.enrich(assigns, opts)

      assert result.event_duration_ms == 0
    end

    test "handles missing measurements" do
      assigns = %{}
      opts = []

      result = Duration.enrich(assigns, opts)

      assert result.event_duration_ms == nil
    end

    test "handles nil measurements" do
      assigns = %{}
      opts = [measurements: nil]

      result = Duration.enrich(assigns, opts)

      assert result.event_duration_ms == nil
    end

    test "handles measurements without duration" do
      assigns = %{}
      opts = [measurements: %{other_field: 123}]

      result = Duration.enrich(assigns, opts)

      assert result.event_duration_ms == nil
    end

    test "converts duration to integer milliseconds" do
      assigns = %{}
      # 1234 milliseconds in native units
      duration_native = System.convert_time_unit(1234, :millisecond, :native)
      opts = [measurements: %{duration: duration_native}]

      result = Duration.enrich(assigns, opts)

      assert result.event_duration_ms == 1234
    end
  end
end
