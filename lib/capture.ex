defmodule Excessibility.Capture do
  @moduledoc """
  Tracks capture state for auto-snapshot functionality.

  When `@tag capture_snapshots: true` is used, this module tracks:
  - Event sequence (counter)
  - Previous snapshot name
  - Test metadata
  - Timeline events
  """

  @doc """
  Initializes capture state for a test.
  """
  def init_capture(test_name, opts \\ []) do
    state = %{
      test_name: test_name,
      sequence: 0,
      events: [],
      opts: opts,
      start_time: DateTime.utc_now()
    }

    Process.put(:excessibility_capture_state, state)
  end

  @doc """
  Returns the current capture state, or nil if not capturing.
  """
  def get_state do
    Process.get(:excessibility_capture_state)
  end

  @doc """
  Records a snapshot event and increments the sequence counter.
  Returns metadata for the snapshot.
  """
  def record_event(event_type, assigns \\ %{}) do
    case get_state() do
      nil ->
        nil

      state ->
        sequence = state.sequence + 1

        event = %{
          sequence: sequence,
          type: event_type,
          timestamp: DateTime.utc_now(),
          assigns: assigns
        }

        updated_events = state.events ++ [event]

        updated_state = %{
          state
          | sequence: sequence,
            events: updated_events
        }

        Process.put(:excessibility_capture_state, updated_state)

        %{
          test_name: state.test_name,
          sequence: sequence,
          event_type: event_type,
          timestamp: event.timestamp,
          assigns: assigns,
          previous: get_previous_snapshot_name(state),
          opts: state.opts
        }
    end
  end

  @doc """
  Returns the timeline of all events for the current test.
  """
  def get_timeline do
    case get_state() do
      nil ->
        nil

      state ->
        %{
          test_name: state.test_name,
          start_time: state.start_time,
          events: state.events,
          total_events: length(state.events)
        }
    end
  end

  @doc """
  Saves the timeline to a JSON file.
  """
  def save_timeline do
    case get_timeline() do
      nil ->
        :ok

      timeline ->
        output_path =
          Application.get_env(
            :excessibility,
            :excessibility_output_path,
            "test/excessibility"
          )

        timelines_path = Path.join(output_path, "timelines")
        File.mkdir_p!(timelines_path)

        filename = "#{timeline.test_name}_timeline.json"
        path = Path.join(timelines_path, filename)

        json = Jason.encode!(timeline, pretty: true)
        File.write!(path, json)

        :ok
    end
  end

  @doc """
  Clears the capture state.
  """
  def clear_state do
    Process.delete(:excessibility_capture_state)
  end

  defp get_previous_snapshot_name(%{sequence: 0}), do: nil

  defp get_previous_snapshot_name(%{test_name: test_name, sequence: seq}) do
    "#{test_name}_#{seq}.html"
  end
end
