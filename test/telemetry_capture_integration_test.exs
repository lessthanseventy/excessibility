defmodule Excessibility.TelemetryCaptureIntegrationTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture

  setup do
    # Clean up any existing snapshots
    :ets.whereis(:excessibility_snapshots) != :undefined &&
      :ets.delete_all_objects(:excessibility_snapshots)

    output_path = "test/excessibility"
    File.rm_rf!(output_path)

    :ok
  end

  test "write_snapshots generates timeline.json" do
    # Attach telemetry
    TelemetryCapture.attach()

    # Simulate capturing snapshots
    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :mount, :stop],
      %{duration: 100},
      %{
        socket: %{
          assigns: %{user_id: 123, products: []},
          view: MyApp.Live
        }
      },
      nil
    )

    :timer.sleep(10)

    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: 50},
      %{
        socket: %{
          assigns: %{user_id: 123, products: [%{id: 1}]},
          view: MyApp.Live
        },
        params: %{"event" => "add_product"}
      },
      nil
    )

    # Write snapshots
    TelemetryCapture.write_snapshots("integration_test")

    # Verify timeline.json exists
    timeline_path = "test/excessibility/timeline.json"
    assert File.exists?(timeline_path)

    # Verify timeline content
    timeline = timeline_path |> File.read!() |> Jason.decode!()
    assert timeline["test"] == "integration_test"
    assert length(timeline["timeline"]) == 2

    first_event = Enum.at(timeline["timeline"], 0)
    assert first_event["event"] == "mount"
    assert first_event["sequence"] == 1

    second_event = Enum.at(timeline["timeline"], 1)
    assert second_event["event"] == "handle_event:add_product"
    assert second_event["changes"] != nil

    # Cleanup
    TelemetryCapture.detach()
    File.rm_rf!("test/excessibility")
  end
end
