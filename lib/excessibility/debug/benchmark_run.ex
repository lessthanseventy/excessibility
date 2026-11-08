defmodule Excessibility.Debug.BenchmarkRun do
  @moduledoc """
  The `--benchmark=N` loop of `mix excessibility.debug`: runs the test N times,
  collects per-callback and per-query durations, and writes `benchmark.json`
  through `Excessibility.Benchmark`.
  """

  import Excessibility.Paths

  alias Excessibility.TelemetryCapture.Formatter
  alias Mix.Tasks.Excessibility.Debug

  # Benchmark loop: run the test `runs` times, collect one timing sample per
  # run from the freshly written timeline.json, summarize with robust cold/warm
  # stats, and write benchmark.json. The heavy lifting (stats) lives in the pure
  # `Excessibility.Benchmark` module; this only orchestrates and reads samples.
  def run_benchmark(runs, test_args) when runs > 0 do
    output_path = output_path()
    timeline_path = Path.join(output_path, "timeline.json")

    samples =
      Enum.map(1..runs, fn i ->
        Mix.shell().info("Benchmark run #{i}/#{runs}")
        Debug.run_test(test_args)

        if File.exists?(timeline_path) do
          timeline_path |> File.read!() |> Jason.decode!(keys: :atoms) |> collect_sample()
        else
          %{}
        end
      end)

    summary = Excessibility.Benchmark.summarize(samples)

    File.mkdir_p!(output_path)
    benchmark_path = Path.join(output_path, "benchmark.json")
    File.write!(benchmark_path, Formatter.format_json(summary))

    print_benchmark_summary(summary, benchmark_path)
  end

  def run_benchmark(_runs, _test_args) do
    Mix.shell().error("--benchmark requires a positive integer, e.g. --benchmark=20")
    exit({:shutdown, 1})
  end

  def print_benchmark_summary(summary, benchmark_path) do
    Mix.shell().info("\nBenchmark: #{summary.runs} run(s) (run 1 cold, 2.. warm)")
    Mix.shell().info("Warm keys measured: #{map_size(summary.warm)}")
    Mix.shell().info("Advisory outliers: #{length(summary.outliers)}")

    Enum.each(summary.notes, fn note -> Mix.shell().info("Note: #{note}") end)

    Mix.shell().info("Timing is diagnostic only: green = no relative outlier in these samples, not \"fast.\"")

    Mix.shell().info("📊 Benchmark written to: #{benchmark_path}")
  end

  # Pure sample extraction from a decoded (keys: :atoms) timeline map. Produces a
  # flat `%{key => duration_ms}` map with `"<view>/<callback>"` keys (from
  # `event_duration_ms`, falling back to `duration_since_previous_ms`) and
  # `"query:<fingerprint>"` keys (summed `duration_ms` per fingerprint).
  # Extracted so it is unit-testable without shelling out to `mix test`.
  @doc false
  def collect_sample(timeline_map) do
    timeline_map
    |> Map.get(:timeline, [])
    |> Enum.reduce(%{}, fn event, acc ->
      acc
      |> add_callback_duration(event)
      |> add_query_durations(event)
    end)
  end

  defp add_callback_duration(acc, event) do
    view = event |> Map.get(:view_module) |> view_key()
    callback = Map.get(event, :event, "unknown")
    duration = Map.get(event, :event_duration_ms) || Map.get(event, :duration_since_previous_ms) || 0
    Map.update(acc, "#{view}/#{callback}", duration, &(&1 + duration))
  end

  defp add_query_durations(acc, event) do
    event
    |> Map.get(:ecto_queries, [])
    |> List.wrap()
    |> Enum.reduce(acc, fn query, inner ->
      case Map.get(query, :fingerprint) do
        nil -> inner
        fp -> Map.update(inner, "query:#{fp}", query_duration(query), &(&1 + query_duration(query)))
      end
    end)
  end

  defp query_duration(query), do: Map.get(query, :duration_ms) || 0

  defp view_key(nil), do: "unknown"
  defp view_key(view) when is_binary(view), do: view
  defp view_key(view), do: view |> to_string() |> String.replace_prefix("Elixir.", "")
end
