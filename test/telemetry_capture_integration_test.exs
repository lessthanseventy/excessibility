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

  test "write_snapshots handles functions in assigns" do
    # Attach telemetry
    TelemetryCapture.attach()

    # Simulate capturing snapshots with functions in assigns
    callback = fn -> :ok end
    handler = fn x -> x + 1 end

    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :mount, :stop],
      %{duration: 100},
      %{
        socket: %{
          assigns: %{
            user_id: 123,
            on_click: callback,
            transform: handler,
            nested: %{
              data: "value",
              handler: callback
            }
          },
          view: MyApp.Live
        }
      },
      nil
    )

    # Write snapshots - should not raise on function encoding
    TelemetryCapture.write_snapshots("function_test")

    # Verify timeline.json exists and is valid JSON
    timeline_path = "test/excessibility/timeline.json"
    assert File.exists?(timeline_path)

    timeline = timeline_path |> File.read!() |> Jason.decode!()
    assert timeline["test"] == "function_test"

    # Verify functions were filtered out
    first_event = Enum.at(timeline["timeline"], 0)
    key_state = first_event["key_state"]

    # Should have user_id but not the function fields
    assert key_state["user_id"] == 123
    refute Map.has_key?(key_state, "on_click")
    refute Map.has_key?(key_state, "transform")

    # Cleanup
    TelemetryCapture.detach()
    File.rm_rf!("test/excessibility")
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
