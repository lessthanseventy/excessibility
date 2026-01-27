defmodule Excessibility.TelemetryCapture.Enrichers.Duration do
  @moduledoc """
  Enriches timeline events with duration information.

  Extracts:
  - Event duration from telemetry measurements

  ## Usage

  Runs automatically during timeline building. Adds event_duration_ms
  to each timeline event.

  ## Example Output

      %{
        sequence: 3,
        event: "handle_event:filter",
        event_duration_ms: 45
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :duration

  def enrich(_assigns, opts) do
    measurements = Keyword.get(opts, :measurements, %{})
    duration_ms = extract_duration_ms(measurements)

    %{
      event_duration_ms: duration_ms
    }
  end

  defp extract_duration_ms(nil), do: nil

  defp extract_duration_ms(%{duration: duration}) when is_integer(duration) do
    # Phoenix telemetry uses native time units
    # Convert to milliseconds and round
    System.convert_time_unit(duration, :native, :millisecond)
  end

  defp extract_duration_ms(_), do: nil
end
