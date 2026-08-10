defmodule Excessibility.Benchmark do
  @moduledoc """
  Pure, robust statistics for benchmark mode (`mix excessibility.debug --benchmark=N`).

  Benchmark mode loops a test N times and collects, per run, a map of
  measurement key to `duration_ms`. `summarize/2` turns those per-run samples
  into a value-free `benchmark.json` artifact.

  ## Timing contract

  Timing is diagnostic, never comparable across environments and never part of
  the digest. A key being free of outliers means "no *relative* outlier in these
  samples," **not** "fast." Robust stats (median + MAD) are used deliberately
  instead of mean/stddev so a single slow run cannot skew the picture.

  Sample 1 is treated as **cold** (first-run costs: compilation, connection
  warmup, cold caches). Samples 2..N are **warm**. Cold and warm are reported
  separately per the timing contract; mixing them would poison the median.

  ## Input shape

  `samples` is a list (one entry per run, in run order) of maps:

      [
        %{"MyLive/mount" => 12.0, "query:sha256:aaa" => 5.0},
        %{"MyLive/mount" => 6.0,  "query:sha256:aaa" => 3.0},
        ...
      ]

  Keys are opaque strings (the mix task uses `"<view>/<callback>"` and
  `"query:<fingerprint>"`); values are `duration_ms` numbers. Keys may vary
  between runs — each key is summarized over the runs in which it appears.

  ## Output shape

      %{
        schema: "excessibility.benchmark/v1",
        runs: n,
        cold: %{key => %{median: number, mad: number, sample: number}},  # run 1 only
        warm: %{key => %{median: number, mad: number, samples: integer}}, # runs 2..n
        outliers: [
          %{key: String.t(), run: pos_integer(), value: number,
            median: number, mad: number, threshold: number}
        ],
        notes: [String.t()]
      }

  `outliers` is **advisory only** — a warm sample where
  `value > median + k * mad` (k defaults to 6, configurable via `:k`). It never
  encodes a pass/fail verdict; the raw `value`, `median`, `mad`, `threshold`,
  and 1-based `run` index are attached so a reader can judge for themselves.
  """

  @schema "excessibility.benchmark/v1"
  @default_k 6

  @doc """
  Median of a list of numbers.

  Returns the middle element (odd length) or the mean of the two middle
  elements (even length). Returns `nil` for an empty list.
  """
  def median([]), do: nil

  def median(numbers) when is_list(numbers) do
    sorted = Enum.sort(numbers)
    count = length(sorted)
    mid = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  @doc """
  Median Absolute Deviation: `median(for x <- xs, do: abs(x - median(xs)))`.

  A robust measure of spread. Returns `nil` for an empty list and `0` when all
  values are identical.
  """
  def mad([]), do: nil

  def mad(numbers) when is_list(numbers) do
    med = median(numbers)
    median(for x <- numbers, do: abs(x - med))
  end

  @doc """
  Summarize per-run samples into the robust cold/warm benchmark artifact.

  Options:

    * `:k` - outlier multiplier; a warm sample is flagged when it exceeds
      `median + k * mad`. Defaults to `#{@default_k}`.
  """
  def summarize(samples, opts \\ []) when is_list(samples) do
    k = Keyword.get(opts, :k, @default_k)
    runs = length(samples)
    indexed = Enum.with_index(samples, 1)

    cold_sample =
      case indexed do
        [{run1, 1} | _] -> run1
        _ -> %{}
      end

    warm_indexed = Enum.drop(indexed, 1)
    warm = build_warm(warm_indexed)

    %{
      schema: @schema,
      runs: runs,
      cold: build_cold(cold_sample),
      warm: warm,
      outliers: detect_outliers(warm_indexed, warm, k),
      notes: notes_for(runs)
    }
  end

  defp build_cold(sample) do
    Map.new(sample, fn {key, value} ->
      {key, %{median: value, mad: 0, sample: value}}
    end)
  end

  defp build_warm(warm_indexed) do
    warm_indexed
    |> values_by_key()
    |> Map.new(fn {key, values} ->
      {key, %{median: median(values), mad: mad(values), samples: length(values)}}
    end)
  end

  # %{key => [value, ...]} across the given runs, preserving run order.
  defp values_by_key(indexed_runs) do
    Enum.reduce(indexed_runs, %{}, fn {run_map, _run}, acc ->
      Enum.reduce(run_map, acc, fn {key, value}, inner ->
        Map.update(inner, key, [value], &(&1 ++ [value]))
      end)
    end)
  end

  defp detect_outliers(warm_indexed, warm, k) do
    for_result =
      for {run_map, run} <- warm_indexed,
          {key, value} <- run_map,
          stats = Map.get(warm, key),
          stats != nil,
          threshold = stats.median + k * stats.mad,
          value > threshold do
        %{
          key: key,
          run: run,
          value: value,
          median: stats.median,
          mad: stats.mad,
          threshold: threshold
        }
      end

    Enum.sort_by(for_result, &{&1.key, &1.run})
  end

  defp notes_for(runs) when runs < 2 do
    ["only #{runs} run(s); warm stats require >= 2 runs (run 1 is cold)"]
  end

  defp notes_for(_runs), do: []
end
