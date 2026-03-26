defmodule Excessibility.TelemetryCapture.Enrichers.PushEvents do
  @moduledoc """
  Enriches timeline events with push_event call information.

  Instruments `Phoenix.LiveView.push_event/3` calls via telemetry.
  Uses an Agent-based store for test-scoped event tracking.

  ## Example Output

      %{
        push_events: [%{event_name: "update-chart", payload_size: 450}],
        push_event_count: 1
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  @handler_id "excessibility-push-events"

  def name, do: :push_events
  def cost, do: :moderate

  def enrich(_assigns, opts) do
    events = Keyword.get(opts, :push_events, [])

    %{
      push_events: events,
      push_event_count: length(events)
    }
  end

  # --- Telemetry handler ---

  def attach do
    :telemetry.attach(
      @handler_id,
      [:phoenix, :live_view, :push_event],
      &handle_push_event/4,
      nil
    )

    :ok
  rescue
    _ -> :ok
  end

  def detach do
    :telemetry.detach(@handler_id)
    :ok
  rescue
    _ -> :ok
  end

  defp handle_push_event(_event, _measurements, metadata, _config) do
    record = %{
      event_name: Map.get(metadata, :event, "unknown"),
      payload_size: estimate_payload_size(Map.get(metadata, :payload, %{}))
    }

    record_push_event(record)
  end

  defp estimate_payload_size(payload) do
    payload |> :erlang.term_to_binary() |> byte_size()
  end

  # --- Agent-based store ---

  def start_store do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def stop_store do
    if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    :ok
  end

  def record_push_event(record) do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, &[record | &1])
    end
  end

  def get_push_events do
    if Process.whereis(__MODULE__) do
      Agent.get(__MODULE__, &Enum.reverse/1)
    else
      []
    end
  end

  def clear do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn _ -> [] end)
    end
  end
end
