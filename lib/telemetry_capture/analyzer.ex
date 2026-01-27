defmodule Excessibility.TelemetryCapture.Analyzer do
  @moduledoc """
  Behaviour for timeline analyzers.

  Analyzers detect patterns across complete timelines and return structured findings.
  Analyzers are selectively enabled via CLI flags.

  ## Example

      defmodule MyApp.CustomAnalyzer do
        @behaviour Excessibility.TelemetryCapture.Analyzer

        def name, do: :custom
        def default_enabled?, do: false

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
  - `analyze/2` - Takes complete timeline and options, returns analysis results

  ## Types

  Analysis results contain:
  - `:findings` - List of issues found (warnings, errors, info)
  - `:stats` - Summary statistics for the analysis
  """

  @callback name() :: atom()
  @callback default_enabled?() :: boolean()
  @callback analyze(timeline :: map(), opts :: keyword()) :: analysis_result()

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
end
