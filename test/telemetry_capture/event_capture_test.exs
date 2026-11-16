defmodule Excessibility.TelemetryCapture.EventCaptureTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.SnapshotStore
  alias Phoenix.LiveView.Socket

  setup do
    SnapshotStore.ensure_started()
    TelemetryCapture.clear_snapshots()
    on_exit(&TelemetryCapture.clear_snapshots/0)
  end

  defp socket(view), do: %Socket{view: view, assigns: %{__changed__: %{}, count: 1}}

  test "a LiveView handle_event is named from the telemetry metadata, not the payload" do
    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: 10},
      %{socket: socket(MyApp.IndexLive), event: "select_active_view", params: %{"id" => "1"}},
      nil
    )

    assert [%{event_type: "handle_event:select_active_view", component: nil}] = TelemetryCapture.get_snapshots()
  end

  test "a LiveComponent handle_event is captured with its component" do
    TelemetryCapture.handle_event(
      [:phoenix, :live_component, :handle_event, :stop],
      %{duration: 10},
      %{
        socket: socket(MyApp.IndexLive),
        component: MyApp.InputForm,
        event: "validate_input_form",
        params: %{"form" => %{}}
      },
      nil
    )

    assert [
             %{
               event_type: "handle_event:validate_input_form",
               component: MyApp.InputForm,
               view_module: MyApp.IndexLive
             }
           ] = TelemetryCapture.get_snapshots()
  end

  test "attach/0 subscribes to LiveComponent handle_event" do
    TelemetryCapture.attach()
    on_exit(&TelemetryCapture.detach/0)

    :telemetry.execute(
      [:phoenix, :live_component, :handle_event, :stop],
      %{duration: 10},
      %{socket: socket(MyApp.IndexLive), component: MyApp.InputForm, event: "save", params: %{}}
    )

    assert [%{event_type: "handle_event:save"}] = TelemetryCapture.get_snapshots()
  end
end
