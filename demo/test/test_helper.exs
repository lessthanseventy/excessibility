# Enable Excessibility telemetry capture when running under
# `mix excessibility.debug` (which sets EXCESSIBILITY_TELEMETRY_CAPTURE=true).
if System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true" do
  Excessibility.TelemetryCapture.attach()
end

ExUnit.start()
