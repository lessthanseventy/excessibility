defmodule Excessibility.TelemetryCapture.Analyzers.Hypothesis do
  @moduledoc """
  Generates hypotheses about likely root causes.

  Analyzes patterns across enricher data to suggest investigation paths.
  Designed to help LLMs and developers focus debugging efforts.

  Not enabled by default - run with `--analyze=hypothesis`.

  ## Output

      %{
        findings: [
          %{
            severity: :info,
            message: "Memory grew 5.2x. Likely cause: 'items' list is growing unbounded.",
            events: [],
            metadata: %{
              growth_factor: 5.2,
              investigation_steps: [
                "Check which assigns are growing between events",
                "Look for lists that accumulate without limit",
                "Consider pagination or windowing for large datasets"
              ]
            }
          }
        ],
        stats: %{hypothesis_count: 1}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :hypothesis
  def default_enabled?, do: false

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{hypothesis_count: 0}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    hypotheses =
      check_memory_growth(timeline) ++
        check_query_growth(timeline) ++
        check_list_growth(timeline)

    %{
      findings: hypotheses,
      stats: %{hypothesis_count: length(hypotheses)}
    }
  end

  defp check_memory_growth(timeline) do
    sizes =
      timeline
      |> Enum.map(&Map.get(&1, :memory_size, 0))
      |> Enum.filter(&(&1 > 0))

    check_memory_growth_sizes(sizes, timeline)
  end

  defp check_memory_growth_sizes(sizes, _timeline) when length(sizes) < 2, do: []

  defp check_memory_growth_sizes(sizes, timeline) do
    first = List.first(sizes)
    last = List.last(sizes)
    growth = last / max(first, 1)

    if growth > 3 do
      build_memory_finding(growth, timeline)
    else
      []
    end
  end

  defp build_memory_finding(growth, timeline) do
    list_culprit = find_growing_list(timeline)

    message =
      if list_culprit do
        "Memory grew #{Float.round(growth, 1)}x. Likely cause: '#{list_culprit}' list is growing unbounded."
      else
        "Memory grew #{Float.round(growth, 1)}x. Check for accumulating data in assigns."
      end

    [
      %{
        severity: :info,
        message: message,
        events: [],
        metadata: %{
          growth_factor: growth,
          investigation_steps: [
            "Check which assigns are growing between events",
            "Look for lists that accumulate without limit",
            "Consider pagination or windowing for large datasets"
          ]
        }
      }
    ]
  end

  defp check_query_growth(timeline) do
    counts =
      timeline
      |> Enum.map(&Map.get(&1, :query_records_loaded, 0))
      |> Enum.filter(&(&1 > 0))

    if length(counts) >= 2 and List.last(counts) > List.first(counts) * 5 do
      [
        %{
          severity: :info,
          message: "Query record count grew significantly. Possible N+1 - consider preload/join.",
          events: [],
          metadata: %{
            investigation_steps: [
              "Check Ecto queries in handle_event callbacks",
              "Use Repo.preload for associations",
              "Consider Ecto.Query.join for related data"
            ]
          }
        }
      ]
    else
      []
    end
  end

  defp check_list_growth(timeline) do
    with first when not is_nil(first) <- List.first(timeline),
         last when not is_nil(last) <- List.last(timeline) do
      find_growing_lists_finding(first, last)
    else
      _ -> []
    end
  end

  defp find_growing_lists_finding(first, last) do
    first_lists = Map.get(first, :list_sizes, %{})
    last_lists = Map.get(last, :list_sizes, %{})
    growing = find_growing_lists(first_lists, last_lists)

    case Enum.max_by(growing, fn {_k, s} -> s end, fn -> nil end) do
      {key, size} ->
        [
          %{
            severity: :info,
            message: "List '#{key}' grew to #{size} items. Consider pagination.",
            events: [],
            metadata: %{list_name: key, final_size: size}
          }
        ]

      nil ->
        []
    end
  end

  defp find_growing_list(timeline) do
    with first when not is_nil(first) <- List.first(timeline),
         last when not is_nil(last) <- List.last(timeline) do
      first_lists = Map.get(first, :list_sizes, %{})
      last_lists = Map.get(last, :list_sizes, %{})
      growing = find_growing_lists(first_lists, last_lists)

      case Enum.max_by(growing, fn {_key, size} -> size end, fn -> nil end) do
        {key, _size} -> key
        nil -> nil
      end
    end
  end

  defp find_growing_lists(first_lists, last_lists) do
    Enum.filter(last_lists, fn {key, size} ->
      prev_size = Map.get(first_lists, key, 0)
      prev_size > 0 and size > prev_size * 2
    end)
  end
end
