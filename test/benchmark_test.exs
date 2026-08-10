defmodule Excessibility.BenchmarkTest do
  use ExUnit.Case, async: true

  alias Excessibility.Benchmark

  describe "median/1" do
    test "returns the middle element for an odd-length list" do
      assert Benchmark.median([3, 1, 2]) == 2
    end

    test "returns the mean of the two middle elements for an even-length list" do
      assert Benchmark.median([4, 1, 3, 2]) == 2.5
    end

    test "handles a single-element list" do
      assert Benchmark.median([42]) == 42
    end

    test "returns nil for an empty list" do
      assert Benchmark.median([]) == nil
    end

    test "is order-independent" do
      assert Benchmark.median([10, 2, 8, 4, 6]) == Benchmark.median([6, 4, 10, 8, 2])
    end
  end

  describe "mad/1" do
    test "is zero when all values are identical" do
      assert Benchmark.mad([5, 5, 5, 5]) == 0
    end

    test "computes the median absolute deviation" do
      # median = 3; abs deviations = [2,1,0,1,2]; median of those = 1
      assert Benchmark.mad([1, 2, 3, 4, 5]) == 1
    end

    test "matches its definition: median(|x - median(xs)|)" do
      xs = [1, 1, 2, 2, 4, 6, 9]
      med = Benchmark.median(xs)
      expected = Benchmark.median(for x <- xs, do: abs(x - med))
      assert Benchmark.mad(xs) == expected
    end
  end

  describe "summarize/2 cold/warm split" do
    test "run 1 is cold, runs 2..n are warm" do
      samples = [
        %{"View/mount" => 10.0},
        %{"View/mount" => 5.0},
        %{"View/mount" => 6.0},
        %{"View/mount" => 5.0}
      ]

      result = Benchmark.summarize(samples)

      assert result.schema == "excessibility.benchmark/v1"
      assert result.runs == 4

      cold = result.cold["View/mount"]
      assert cold.sample == 10.0
      assert cold.median == 10.0
      assert cold.mad == 0

      warm = result.warm["View/mount"]
      assert warm.samples == 3
      assert warm.median == Benchmark.median([5.0, 6.0, 5.0])
      assert warm.mad == Benchmark.mad([5.0, 6.0, 5.0])
    end

    test "single run: warm is empty and a note explains why" do
      result = Benchmark.summarize([%{"View/mount" => 10.0}])

      assert result.runs == 1
      assert result.cold["View/mount"].sample == 10.0
      assert result.warm == %{}
      assert result.outliers == []
      assert result.notes != []
    end

    test "empty samples produce empty cold/warm and a note" do
      result = Benchmark.summarize([])
      assert result.runs == 0
      assert result.cold == %{}
      assert result.warm == %{}
      assert result.outliers == []
    end
  end

  describe "summarize/2 outlier detection" do
    test "flags a warm sample beyond median + k*mad with raw value attached" do
      # warm runs 2..7: a tight cluster with one extreme spike
      warm = [8.0, 9.0, 8.0, 10.0, 400.0]

      samples = [%{"q" => 8.0} | Enum.map(warm, &%{"q" => &1})]

      result = Benchmark.summarize(samples, k: 6)

      assert [outlier] = result.outliers
      assert outlier.key == "q"
      assert outlier.value == 400.0
      assert outlier.median == Benchmark.median(warm)
      assert outlier.mad == Benchmark.mad(warm)
      assert outlier.threshold == outlier.median + 6 * outlier.mad
      # run index is the global run number (cold is run 1, so the spike is run 6)
      assert outlier.run == 6
    end

    test "a jittery-but-non-outlier warm set yields no outliers" do
      # Real jitter gives mad > 0; nothing here exceeds median + 6*mad.
      # warm = [10,12,14,16,18], median 14, mad 2, threshold 26.
      samples = [
        %{"q" => 10.0},
        %{"q" => 10.0},
        %{"q" => 12.0},
        %{"q" => 14.0},
        %{"q" => 16.0},
        %{"q" => 18.0}
      ]

      assert Benchmark.summarize(samples, k: 6).outliers == []
    end

    test "k is configurable" do
      warm = [10.0, 10.0, 10.0, 25.0]
      samples = [%{"q" => 10.0} | Enum.map(warm, &%{"q" => &1})]

      # mad is 0 here, so any value strictly above the median flags regardless of k
      assert length(Benchmark.summarize(samples, k: 6).outliers) == 1
    end
  end

  describe "summarize/2 effect-size gating (#159)" do
    # Sub-millisecond scheduler/timer jitter clears the MAD threshold but is not
    # an actionable effect. warm = [0.60,0.62,0.62,0.64,0.90]: median 0.62,
    # mad 0.02, threshold 0.74; 0.90 > 0.74 statistically but only +0.28 ms.
    test "a sub-millisecond spike is not flagged despite clearing median + k*mad" do
      warm = [0.60, 0.62, 0.62, 0.64, 0.90]
      samples = [%{"q" => 0.62} | Enum.map(warm, &%{"q" => &1})]

      assert Benchmark.summarize(samples, k: 6).outliers == []
    end

    test "a large absolute-and-relative regression is still flagged" do
      warm = [50.0, 50.0, 50.0, 50.0, 200.0]
      samples = [%{"q" => 50.0} | Enum.map(warm, &%{"q" => &1})]

      assert [outlier] = Benchmark.summarize(samples, k: 6).outliers
      assert outlier.value == 200.0
    end

    test "the effect-size floors are configurable (0 restores pure-statistical flagging)" do
      warm = [0.60, 0.62, 0.62, 0.64, 0.90]
      samples = [%{"q" => 0.62} | Enum.map(warm, &%{"q" => &1})]

      assert [_outlier] =
               Benchmark.summarize(samples, k: 6, min_abs_ms: 0.0, min_rel_factor: 1.0).outliers
    end

    test "small warm-sample counts are labeled weak evidence" do
      # 1 cold + 4 warm = 4 warm samples; MAD-based inference is weak.
      warm = [50.0, 50.0, 50.0, 200.0]
      samples = [%{"q" => 50.0} | Enum.map(warm, &%{"q" => &1})]

      result = Benchmark.summarize(samples, k: 6)

      assert Enum.any?(result.notes, &(&1 =~ "weak"))
      assert [outlier] = result.outliers
      assert outlier.weak_evidence == true
    end
  end

  describe "summarize/2 determinism" do
    test "output is stable across identical inputs" do
      samples = [
        %{"a/x" => 3.0, "b/y" => 7.0},
        %{"a/x" => 2.0, "b/y" => 6.0},
        %{"a/x" => 2.5, "b/y" => 6.5}
      ]

      assert Benchmark.summarize(samples) == Benchmark.summarize(samples)
    end

    test "outliers are sorted by key then run" do
      samples = [
        %{"a" => 1.0, "b" => 1.0},
        %{"a" => 1.0, "b" => 1.0},
        %{"a" => 1.0, "b" => 1.0},
        %{"a" => 100.0, "b" => 100.0}
      ]

      keys = Enum.map(Benchmark.summarize(samples).outliers, & &1.key)
      assert keys == Enum.sort(keys)
    end
  end
end
