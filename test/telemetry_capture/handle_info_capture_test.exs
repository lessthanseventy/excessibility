defmodule Excessibility.TelemetryCapture.HandleInfoCaptureTest do
  @moduledoc """
  Issue #147: the opt-in `on_mount` hook records `handle_info` messages (which
  have no LiveView telemetry) so `message_flooding` can fire. The full capture
  path is exercised end-to-end against a real LiveView in the demo app; here we
  pin the production-safety guarantee — the hook does nothing unless telemetry
  capture is actually running.
  """
  use ExUnit.Case

  alias Excessibility.TelemetryCapture

  setup do
    previous = System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE")
    System.delete_env("EXCESSIBILITY_TELEMETRY_CAPTURE")

    on_exit(fn ->
      if previous, do: System.put_env("EXCESSIBILITY_TELEMETRY_CAPTURE", previous)
    end)

    :ok
  end

  test "on_mount attaches no hook and returns the socket untouched when capture is off" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:cont, returned} = TelemetryCapture.on_mount(:default, %{}, %{}, socket)
    assert returned == socket
  end
end
