defmodule Excessibility.TelemetryCapture.Registry do
  @moduledoc """
  Registry for enrichers and analyzers.

  Provides auto-discovery and lookup functionality for telemetry
  analysis plugins.

  ## Usage

      # Get all enrichers (run automatically)
      Registry.discover_enrichers()

      # Get analyzers that run by default
      Registry.get_default_analyzers()

      # Get specific analyzer by name
      Registry.get_analyzer(:memory)
  """

  # Hard-coded for initial implementation
  # Future: Could use compile-time discovery via @behaviour inspection
  @enrichers [
    Excessibility.TelemetryCapture.Enrichers.CollectionSize,
    Excessibility.TelemetryCapture.Enrichers.Duration,
    Excessibility.TelemetryCapture.Enrichers.Memory,
    Excessibility.TelemetryCapture.Enrichers.Query,
    Excessibility.TelemetryCapture.Enrichers.State
  ]

  @analyzers [
    Excessibility.TelemetryCapture.Analyzers.DataGrowth,
    Excessibility.TelemetryCapture.Analyzers.Memory,
    Excessibility.TelemetryCapture.Analyzers.NPlusOne,
    Excessibility.TelemetryCapture.Analyzers.Performance,
    Excessibility.TelemetryCapture.Analyzers.StateMachine
  ]

  @doc """
  Returns all registered enrichers.

  Enrichers run automatically during timeline building.
  """
  def discover_enrichers, do: @enrichers

  @doc """
  Returns all registered analyzers.
  """
  def discover_analyzers, do: @analyzers

  @doc """
  Returns analyzers that are enabled by default.

  These run unless explicitly disabled via --no-analyze flag.
  """
  def get_default_analyzers do
    Enum.filter(@analyzers, & &1.default_enabled?())
  end

  @doc """
  Returns all analyzers regardless of default_enabled? status.
  """
  def get_all_analyzers, do: @analyzers

  @doc """
  Finds analyzer by name.

  Returns nil if not found.
  """
  def get_analyzer(name) do
    Enum.find(@analyzers, fn analyzer ->
      analyzer.name() == name
    end)
  end
end
