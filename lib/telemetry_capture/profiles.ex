defmodule Excessibility.TelemetryCapture.Profiles do
  @moduledoc """
  Predefined analyzer profiles for common use cases.

  Profiles bundle related analyzers for easy CLI usage:
  - `:quick` - Fast, minimal analysis (event patterns only)
  - `:memory` - Memory-focused analysis
  - `:performance` - Performance-focused analysis
  - `:full` - All analyzers

  ## Usage

      mix excessibility.debug test.exs --profile=memory
  """

  alias Excessibility.TelemetryCapture.Registry

  @profiles %{
    quick: [:event_pattern],
    memory: [:memory, :data_growth],
    performance: [:performance, :event_pattern],
    full: :all
  }

  @doc """
  Gets analyzer names for a profile.
  Returns nil for unknown profiles.
  """
  def get(:full) do
    Enum.map(Registry.get_all_analyzers(), & &1.name())
  end

  def get(profile_name) do
    Map.get(@profiles, profile_name)
  end

  @doc """
  Lists all available profile names.
  """
  def list do
    Map.keys(@profiles)
  end
end
