defmodule Excessibility.TelemetryCapture.Analyzer do
  @moduledoc """
  Behaviour for timeline analyzers.

  Analyzers detect patterns across complete timelines and return structured findings.
  Analyzers declare their enricher dependencies via `requires_enrichers/0`.

  ## Example

      defmodule MyApp.CustomAnalyzer do
        @behaviour Excessibility.TelemetryCapture.Analyzer

        def name, do: :custom
        def default_enabled?, do: false
        def requires_enrichers, do: [:memory, :duration]

        def analyze(timeline, _opts) do
          %{
            findings: [...],
            stats: %{...}
          }
        end
      end

  ## Callbacks

  - `name/0` - Returns atom identifier for this analyzer
  - `default_enabled?/0` - Whether analyzer runs by default without explicit flag
  - `requires_enrichers/0` - (Optional) List of enricher names this analyzer needs
  - `analyze/2` - Takes complete timeline and options, returns analysis results

  ## Types

  Analysis results contain:
  - `:findings` - List of issues found (warnings, errors, info)
  - `:stats` - Summary statistics for the analysis
  """

  @callback name() :: atom()
  @callback default_enabled?() :: boolean()
  @callback requires_enrichers() :: [atom()]
  @callback analyze(timeline :: map(), opts :: keyword()) :: analysis_result()

  @optional_callbacks requires_enrichers: 0

  @type analysis_result :: %{
          findings: [finding()],
          stats: map()
        }

  @type finding :: %{
          severity: :info | :warning | :critical,
          message: String.t(),
          events: [integer()],
          metadata: map()
        }

  @doc """
  Gets required enrichers for an analyzer module.
  Returns empty list if not defined.
  """
  def get_required_enrichers(analyzer_module) do
    if function_exported?(analyzer_module, :requires_enrichers, 0) do
      analyzer_module.requires_enrichers()
    else
      []
    end
  end
end
