defmodule Excessibility.TelemetryCapture do
  @moduledoc """
  Telemetry-based automatic snapshot capture for LiveView tests.

  Attaches to Phoenix LiveView telemetry events to automatically capture
  snapshots when LiveView events occur, with no test code changes required.
  """

  alias Excessibility.TelemetryCapture.Formatter
  alias Excessibility.TelemetryCapture.Timeline

  require Logger

  @doc """
  Attaches telemetry handlers for automatic snapshot capture.

  Call this before running tests to enable auto-capture.
  """
  def attach do
    # Create ETS table for cross-process snapshot storage
    unless :ets.whereis(:excessibility_snapshots) != :undefined do
      :ets.new(:excessibility_snapshots, [:named_table, :public, :bag])
    end

    :telemetry.attach_many(
      "excessibility-capture",
      [
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_view, :handle_params, :stop]
      ],
      &handle_event/4,
      nil
    )
  end

  @doc """
  Detaches telemetry handlers.
  """
  def detach do
    :telemetry.detach("excessibility-capture")
  end

  @doc """
  Handles telemetry events and captures snapshots.
  """
  def handle_event([:phoenix, :live_view, :mount, :stop], measurements, metadata, _config) do
    IO.puts("📸 Excessibility: Telemetry mount event fired!")
    capture_snapshot("mount", measurements, metadata)
  end

  def handle_event([:phoenix, :live_view, :handle_event, :stop], measurements, metadata, _config) do
    event_name =
      try do
        get_in(metadata, [:params, "event"]) || "event"
      rescue
        _ -> "event"
      end

    capture_snapshot("handle_event:#{event_name}", measurements, metadata)
  end

  def handle_event([:phoenix, :live_view, :handle_params, :stop], measurements, metadata, _config) do
    capture_snapshot("handle_params", measurements, metadata)
  end

  defp capture_snapshot(event_type, _measurements, metadata) do
    socket = metadata[:socket]

    if socket do
      clean_assigns = extract_clean_assigns(socket)
      view_module = extract_view_module(socket, metadata)

      store_snapshot(event_type, clean_assigns, view_module, metadata)
    else
      Logger.debug("Excessibility: No socket in metadata for #{event_type}")
    end
  rescue
    error ->
      Logger.warning("Excessibility: Failed to capture snapshot for #{event_type}: #{inspect(error)}")
  end

  defp extract_clean_assigns(socket) do
    assigns =
      cond do
        is_struct(socket.assigns) -> Map.from_struct(socket.assigns)
        is_map(socket.assigns) -> socket.assigns
        true -> %{}
      end

    assigns
    |> Map.drop([:flash, :__changed__, :__temp__])
    |> Enum.filter(fn {k, _v} -> !String.starts_with?(to_string(k), "_") end)
    |> Map.new()
  end

  defp extract_view_module(socket, metadata) do
    cond do
      is_struct(socket) && Map.has_key?(socket, :view) -> socket.view
      is_map(metadata) && Map.has_key?(metadata, :view) -> metadata[:view]
      true -> :unknown
    end
  end

  defp store_snapshot(event_type, clean_assigns, view_module, metadata) do
    key = {DateTime.utc_now(), :erlang.unique_integer([:monotonic])}

    snapshot = %{
      event_type: event_type,
      assigns: clean_assigns,
      timestamp: DateTime.utc_now(),
      view_module: view_module,
      metadata_keys: Map.keys(metadata)
    }

    :ets.insert(:excessibility_snapshots, {key, snapshot})

    IO.puts("✅ Captured telemetry snapshot for #{event_type}")
    Logger.debug("Excessibility: Captured snapshot for #{event_type} with assigns: #{inspect(Map.keys(clean_assigns))}")
  end

  @doc """
  Retrieves all captured snapshots and clears the table.
  """
  def get_snapshots do
    case :ets.whereis(:excessibility_snapshots) do
      :undefined ->
        []

      _table ->
        snapshots =
          :excessibility_snapshots
          |> :ets.tab2list()
          |> Enum.map(fn {_key, snapshot} -> snapshot end)
          |> Enum.sort_by(& &1.timestamp, DateTime)

        snapshots
    end
  end

  @doc """
  Clears all captured snapshots.
  """
  def clear_snapshots(_test_name \\ nil) do
    case :ets.whereis(:excessibility_snapshots) do
      :undefined ->
        :ok

      _table ->
        :ets.delete_all_objects(:excessibility_snapshots)
    end
  end

  @doc """
  Writes captured snapshots to HTML files.
  """
  def write_snapshots(test_name) do
    snapshots = get_snapshots()
    IO.puts("💾 Excessibility: Writing #{length(snapshots)} telemetry snapshots for test #{inspect(test_name)}")

    if snapshots != [] do
      output_path =
        Application.get_env(
          :excessibility,
          :excessibility_output_path,
          "test/excessibility"
        )

      snapshots_path = Path.join(output_path, "html_snapshots")
      File.mkdir_p!(snapshots_path)

      snapshots
      |> Enum.with_index(1)
      |> Enum.each(fn {snapshot, index} ->
        filename = "#{sanitize_test_name(test_name)}_telemetry_#{index}_#{sanitize_event_type(snapshot.event_type)}.html"
        path = Path.join(snapshots_path, filename)

        html = build_snapshot_html(snapshot, index, test_name)
        File.write!(path, html)

        Logger.info("Wrote telemetry snapshot: #{filename}")
      end)

      # Generate and write timeline.json
      timeline = Timeline.build_timeline(snapshots, test_name)
      timeline_json = Formatter.format_json(timeline)
      timeline_path = Path.join(output_path, "timeline.json")
      File.write!(timeline_path, timeline_json)

      IO.puts("📊 Excessibility: Wrote timeline.json")
    end
  end

  defp build_snapshot_html(snapshot, sequence, test_name) do
    """
    <!--
    Excessibility Telemetry Snapshot
    Test: #{test_name}
    Sequence: #{sequence}
    Event: #{snapshot.event_type}
    Timestamp: #{snapshot.timestamp}
    View Module: #{inspect(snapshot.view_module)}
    Assigns: #{inspect(snapshot.assigns, pretty: true)}
    -->

    <html>
      <head>
        <title>Telemetry Snapshot - #{snapshot.event_type}</title>
      </head>
      <body>
        <h1>Telemetry Snapshot: #{snapshot.event_type}</h1>
        <h2>Sequence: #{sequence}</h2>
        <h3>Assigns:</h3>
        <pre>#{inspect(snapshot.assigns, pretty: true)}</pre>
        <p><em>Note: This is a telemetry-captured snapshot. Full HTML rendering requires the LiveView process context.</em></p>
      </body>
    </html>
    """
  end

  defp sanitize_test_name(test_name) when is_atom(test_name) do
    test_name
    |> to_string()
    |> String.replace(" ", "_")
    |> String.replace(~r/[^a-zA-Z0-9_]/, "")
  end

  defp sanitize_test_name(test_name), do: to_string(test_name)

  defp sanitize_event_type(event_type) do
    event_type
    |> to_string()
    |> String.replace(":", "_")
    |> String.replace(" ", "_")
  end
end
