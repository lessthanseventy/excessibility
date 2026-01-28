defmodule Excessibility.TelemetryCapture.Analyzers.AccessibilityCorrelation do
  @moduledoc """
  Correlates state changes with accessibility implications.

  Identifies events that may need accessibility considerations:
  - Modal/dialog opening (focus management)
  - Dynamic content updates (live regions)
  - Error messages (ARIA announcements)
  - List updates (screen reader notifications)

  Not enabled by default - run with `--analyze=accessibility_correlation`.

  ## Output

      %{
        findings: [
          %{
            severity: :info,
            message: "Event handle_event:open_modal changes 'modal_open' - modal state is accessibility-sensitive",
            events: [2],
            metadata: %{
              field: :modal_open,
              type: :modal,
              recommendations: ["Focus management needed - trap focus in modal"]
            }
          }
        ],
        stats: %{a11y_concerns: 1}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  @a11y_sensitive_patterns [
    {:modal, ~w(modal dialog drawer sheet popup overlay), "Focus management needed - trap focus in modal"},
    {:error, ~w(error alert warning message notification), "Use role=\"alert\" or aria-live for announcements"},
    {:loading, ~w(loading spinner pending), "Announce loading state to screen readers"},
    {:list, ~w(items list results data rows), "Consider aria-live=\"polite\" for list updates"}
  ]

  def name, do: :accessibility_correlation
  def default_enabled?, do: false

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{a11y_concerns: 0}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    findings =
      Enum.flat_map(timeline, &check_event/1)

    %{
      findings: findings,
      stats: %{a11y_concerns: length(findings)}
    }
  end

  defp check_event(%{changes: nil}), do: []
  defp check_event(%{changes: changes}) when map_size(changes) == 0, do: []

  defp check_event(%{changes: changes, sequence: seq, event: event}) do
    Enum.flat_map(changes, fn {field, _value} -> check_field_a11y(field, seq, event) end)
  end

  defp check_event(_), do: []

  defp check_field_a11y(field, seq, event) do
    field_str = field |> to_string() |> String.downcase()

    @a11y_sensitive_patterns
    |> Enum.filter(fn {_type, patterns, _rec} ->
      Enum.any?(patterns, &String.contains?(field_str, &1))
    end)
    |> Enum.map(fn {type, _patterns, recommendation} ->
      %{
        severity: :info,
        message: "Event #{event} changes '#{field}' - #{type} state is accessibility-sensitive",
        events: [seq],
        metadata: %{
          field: field,
          type: type,
          recommendations: [recommendation]
        }
      }
    end)
  end
end
