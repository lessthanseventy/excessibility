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

  Converts tuples to lists and structs to maps for JSON compatibility.
  Removes Ecto `__meta__` fields from converted structs.
  """
  def format_json(timeline) do
    timeline
    |> prepare_for_json()
    |> Jason.encode!(pretty: true)
  end

  # Handle tuples first (convert to lists for JSON)
  defp prepare_for_json(data) when is_tuple(data) do
    data |> Tuple.to_list() |> prepare_for_json()
  end

  # Handle lists
  defp prepare_for_json(data) when is_list(data) do
    Enum.map(data, &prepare_for_json/1)
  end

  # Handle structs (convert to maps for JSON encoding)
  defp prepare_for_json(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> prepare_for_json()
  end

  # Handle regular maps
  defp prepare_for_json(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, prepare_for_json(v)} end)
  end

  # Handle functions - convert to string representation (defense-in-depth)
  defp prepare_for_json(data) when is_function(data) do
    info = Function.info(data)
    "#Function<#{info[:name]}/#{info[:arity]}>"
  end

  # Handle primitives
  defp prepare_for_json(data), do: data

  @doc """
  Formats timeline as markdown report.

  Includes:
  - Summary header
  - Timeline table
  - Detailed change sections
  - Optional full snapshots (if snapshots provided)
  """
  def format_markdown(timeline, _snapshots) do
    """
    # Test Debug Report: #{timeline.test}

    **Duration:** #{timeline.duration_ms}ms

    ## Event Timeline

    #{build_timeline_table(timeline.timeline)}

    ## Detailed Changes

    #{build_detailed_changes(timeline.timeline)}
    """
  end

  defp build_timeline_table(entries) do
    header = "| # | Time | Event | Key Changes |\n|---|------|-------|-------------|"

    rows =
      Enum.map_join(entries, "\n", fn entry ->
        time = "+#{entry.duration_since_previous_ms || 0}ms"
        changes = format_key_changes(entry.changes)
        "| #{entry.sequence} | #{time} | #{entry.event} | #{changes} |"
      end)

    header <> "\n" <> rows
  end

  defp format_key_changes(nil), do: ""

  defp format_key_changes(changes) when map_size(changes) == 0, do: ""

  defp format_key_changes(changes) do
    changes
    |> Enum.take(3)
    |> Enum.map_join(", ", fn {field, value} ->
      {old, new} = normalize_change_value(value)
      "#{field}: #{inspect(old)}→#{inspect(new)}"
    end)
  end

  defp build_detailed_changes(entries) do
    entries
    |> Enum.filter(fn entry -> entry.changes != nil and map_size(entry.changes) > 0 end)
    |> Enum.map_join("\n\n---\n\n", &format_detailed_change/1)
  end

  defp format_detailed_change(entry) do
    """
    ### Event #{entry.sequence}: #{entry.event} (+#{entry.duration_since_previous_ms || 0}ms)

    **State Changes:**
    #{format_change_list(entry.changes)}

    **Key State:**
    ```elixir
    #{inspect(entry.key_state, pretty: true)}
    ```
    """
  end

  defp format_change_list(changes) do
    Enum.map_join(changes, "\n", fn {field, value} ->
      {old, new} = normalize_change_value(value)
      "- `#{field}`: #{inspect(old)} → #{inspect(new)}"
    end)
  end

  # Handle both tuple format (in-memory) and list format (from JSON)
  defp normalize_change_value({old, new}), do: {old, new}
  defp normalize_change_value([old, new]), do: {old, new}

  @doc """
  Formats analysis results as markdown.

  Takes map of analyzer_name => %{findings: [...], stats: %{...}}
  and produces formatted markdown sections.

  ## Options

  - `:verbose` - Include detailed stats even when no issues found (default: false)
  """
  def format_analysis_results(analysis_results, opts \\ [])

  def format_analysis_results(analysis_results, _opts) when map_size(analysis_results) == 0 do
    ""
  end

  def format_analysis_results(analysis_results, opts) do
    verbose? = Keyword.get(opts, :verbose, false)

    analysis_results
    |> Enum.map(fn {name, result} ->
      format_analyzer_section(name, result, verbose?)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp format_analyzer_section(name, %{findings: findings, stats: stats}, verbose?) do
    title = name |> to_string() |> String.capitalize()

    if Enum.empty?(findings) do
      format_healthy_section(title, stats, verbose?)
    else
      format_findings_section(title, findings, stats)
    end
  end

  defp format_healthy_section(title, stats, verbose?) do
    summary = format_summary_stats(stats)

    basic = "## #{title} Analysis ✅\n#{summary}"

    if verbose? and map_size(stats) > 0 do
      basic <> "\n\n" <> format_detailed_stats(stats)
    else
      basic
    end
  end

  defp format_findings_section(title, findings, stats) do
    findings_text = format_findings(findings)
    summary = if map_size(stats) > 0, do: "\n\n#{format_summary_stats(stats)}", else: ""

    "## #{title} Analysis\n#{findings_text}#{summary}"
  end

  defp format_findings(findings) do
    Enum.map_join(findings, "\n", fn finding ->
      emoji =
        case finding.severity do
          :critical -> "🔴"
          :warning -> "⚠️"
          :info -> "ℹ️"
        end

      "#{emoji} #{finding.message}"
    end)
  end

  defp format_summary_stats(stats) when map_size(stats) == 0, do: ""

  defp format_summary_stats(stats) do
    parts = []

    parts =
      if stats[:min] && stats[:max] do
        ["Memory range: #{format_bytes(stats.min)} → #{format_bytes(stats.max)}" | parts]
      else
        parts
      end

    parts =
      if stats[:avg] do
        last = List.first(parts, "")
        updated = last <> " (avg: #{format_bytes(stats.avg)})"
        [updated | List.delete(parts, last)]
      else
        parts
      end

    Enum.join(parts, "\n")
  end

  defp format_detailed_stats(stats) do
    [
      "**Detailed Statistics:**",
      "- Min: #{format_bytes(stats[:min] || 0)}",
      "- Max: #{format_bytes(stats[:max] || 0)}",
      "- Average: #{format_bytes(stats[:avg] || 0)}",
      if(stats[:median], do: "- Median: #{format_bytes(stats.median)}"),
      if(stats[:std_dev], do: "- Std Dev: #{format_bytes(stats.std_dev)}"),
      if(stats[:median_delta],
        do: "- Median Delta: #{format_bytes(stats.median_delta)}"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
