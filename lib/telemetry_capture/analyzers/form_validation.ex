defmodule Excessibility.TelemetryCapture.Analyzers.FormValidation do
  @moduledoc """
  Analyzes form validation patterns.

  Detects excessive validation roundtrips without form submission.
  This may indicate UX issues (too many server calls) or missing debouncing.

  Threshold: >5 validations without submit triggers warning.

  ## Output

      %{
        findings: [
          %{
            severity: :warning,
            message: "7 consecutive validations without submit - consider debouncing",
            events: [],
            metadata: %{streak: 7}
          }
        ],
        stats: %{
          validation_count: 10,
          submit_count: 1,
          max_validation_streak: 7
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  @excessive_threshold 5

  def name, do: :form_validation
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{
      findings: [],
      stats: %{validation_count: 0, submit_count: 0, max_validation_streak: 0}
    }
  end

  def analyze(%{timeline: timeline}, _opts) do
    {validation_count, submit_count, max_streak} = analyze_validation_flow(timeline)

    stats = %{
      validation_count: validation_count,
      submit_count: submit_count,
      max_validation_streak: max_streak
    }

    findings =
      if max_streak > @excessive_threshold do
        [
          %{
            severity: :warning,
            message: "#{max_streak} consecutive validations without submit - consider debouncing",
            events: [],
            metadata: %{streak: max_streak}
          }
        ]
      else
        []
      end

    %{findings: findings, stats: stats}
  end

  defp analyze_validation_flow(timeline) do
    {validation_count, submit_count, current_streak, max_streak} =
      Enum.reduce(timeline, {0, 0, 0, 0}, fn entry, {v_count, s_count, streak, max} ->
        cond do
          validation_event?(entry) ->
            new_streak = streak + 1
            {v_count + 1, s_count, new_streak, max(max, new_streak)}

          submit_event?(entry) ->
            {v_count, s_count + 1, 0, max}

          true ->
            {v_count, s_count, streak, max}
        end
      end)

    {validation_count, submit_count, max(current_streak, max_streak)}
  end

  defp validation_event?(%{event: event}) do
    String.contains?(event, "validate")
  end

  defp submit_event?(%{event: event}) do
    String.contains?(event, "submit") or String.contains?(event, "save")
  end
end
