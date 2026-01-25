defmodule Excessibility.TelemetryCapture.Formatter do
  @moduledoc """
  Formats telemetry timeline data for different output formats.

  Supports:
  - JSON (machine-readable)
  - Markdown (human/AI-readable)
  - Package (directory with multiple files)
  """

  @doc """
  Formats timeline as JSON.
  """
  def format_json(timeline) do
    Jason.encode!(timeline, pretty: true)
  end
end
