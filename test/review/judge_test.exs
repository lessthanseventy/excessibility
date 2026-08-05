defmodule Excessibility.Review.JudgeTest do
  use ExUnit.Case, async: true

  alias Excessibility.Review
  alias Excessibility.Review.Judge
  alias Excessibility.Review.Judge.Heuristic
  alias Excessibility.Review.Judge.LLM

  defmodule CriticalStubAnalyzer do
    @moduledoc false
    @behaviour Excessibility.TelemetryCapture.Analyzer

    @impl true
    def name, do: :stub
    @impl true
    def default_enabled?, do: false
    @impl true
    def analyze(_timeline, _opts) do
      %{findings: [%{severity: :critical, message: "N+1 query in orders", events: [], metadata: %{}}], stats: %{}}
    end
  end

  # A change that introduces a serious (keyboard-inaccessible) violation.
  defp block_change do
    Review.review_pair("editor", "<div>Save</div>", ~s(<div phx-click="save">Save</div>))
  end

  # A change with no DOM/a11y issue but a critical behavioral finding.
  defp behavioral_change do
    Review.review_pair("orders", "<div>x</div>", "<div>x</div>",
      timeline: %{},
      analyzers: [CriticalStubAnalyzer]
    )
  end

  describe "Heuristic judge" do
    test "mirrors the change tier and turns findings into risks" do
      verdict = Heuristic.judge(block_change(), [])

      assert verdict.tier == :block
      assert verdict.source == :heuristic
      assert verdict.confidence == nil
      assert verdict.blast_radius =~ "finding"
      assert [%{severity: "serious", area: "div"}] = verdict.risks
    end
  end

  describe "LLM judge" do
    test "calls the injected completion and parses its verdict" do
      completion = fn prompt ->
        # The prompt should describe the change for the model.
        send(self(), {:prompt, prompt})

        {:ok,
         ~s({"tier":"review","blast_radius":"submit disabled on error","risks":[{"severity":"high","area":"#pay","detail":"now disabled"}],"confidence":0.8})}
      end

      verdict = LLM.judge(block_change(), completion: completion)

      assert verdict.tier == :review
      assert verdict.source == :llm
      assert verdict.confidence == 0.8
      assert verdict.blast_radius =~ "disabled"
      assert [%{severity: "high", area: "#pay"}] = verdict.risks
      assert_received {:prompt, prompt}
      assert prompt =~ "editor"
    end

    test "falls back to the heuristic when the completion errors" do
      verdict = LLM.judge(block_change(), completion: fn _ -> {:error, :timeout} end)

      assert verdict.source == :heuristic
      assert verdict.tier == :block
    end

    test "falls back to the heuristic on unparseable output" do
      verdict = LLM.judge(block_change(), completion: fn _ -> {:ok, "not json"} end)

      assert verdict.source == :heuristic
    end

    test "falls back to the heuristic when the model replies with a JSON array" do
      # Valid JSON, wrong shape — a common LLM failure mode. Must not
      # leak the decoded list out as the "verdict".
      verdict = LLM.judge(block_change(), completion: fn _ -> {:ok, "[]"} end)

      assert verdict.source == :heuristic
      assert verdict.tier == :block
    end

    test "falls back to the heuristic when the completion raises" do
      verdict = LLM.judge(block_change(), completion: fn _ -> raise "boom" end)

      assert verdict.source == :heuristic
      assert verdict.tier == :block
    end

    test "falls back to the heuristic when no completion is configured" do
      assert LLM.judge(block_change(), []).source == :heuristic
    end
  end

  describe "reading behavioral (telemetry) findings" do
    test "heuristic folds behavioral findings into risks and the tier" do
      verdict = Heuristic.judge(behavioral_change(), [])

      assert verdict.tier == :block
      assert verdict.blast_radius =~ "behavioral"
      assert Enum.any?(verdict.risks, &(&1.detail =~ "N+1"))
    end

    test "LLM prompt includes the behavioral findings" do
      completion = fn prompt ->
        send(self(), {:prompt, prompt})
        {:ok, ~s({"tier":"review","blast_radius":"x","risks":[],"confidence":0.5})}
      end

      LLM.judge(behavioral_change(), completion: completion)

      assert_received {:prompt, prompt}
      assert prompt =~ "Behavioral findings"
      assert prompt =~ "N+1"
    end
  end

  describe "verdict/2 dispatch" do
    test "defaults to the heuristic judge" do
      assert Judge.verdict(block_change()).source == :heuristic
    end

    test "honors an explicit :judge module" do
      assert Judge.verdict(block_change(), judge: LLM, completion: fn _ -> {:error, :x} end).source ==
               :heuristic
    end
  end

  describe "verdict/2 tier floor" do
    defp auto_change do
      Review.review_pair("home", "<div>hi</div>", "<div>hi</div>")
    end

    defp completion_replying(tier) do
      fn _prompt ->
        {:ok, ~s({"tier":"#{tier}","blast_radius":"model says so","risks":[],"confidence":0.9})}
      end
    end

    test "floors a model's :auto verdict to :review when the heuristic says :block" do
      verdict = Judge.verdict(block_change(), judge: LLM, completion: completion_replying("auto"))

      assert verdict.tier == :review
      assert verdict.judge_tier == :auto
      assert verdict.source == :llm
    end

    test "allows a model to downgrade :block to :review" do
      verdict = Judge.verdict(block_change(), judge: LLM, completion: completion_replying("review"))

      assert verdict.tier == :review
      refute Map.has_key?(verdict, :judge_tier)
    end

    test "allows a judge to raise the tier without restriction" do
      verdict = Judge.verdict(auto_change(), judge: LLM, completion: completion_replying("block"))

      assert verdict.tier == :block
    end

    test "a model's :auto verdict on an :auto change is untouched" do
      verdict = Judge.verdict(auto_change(), judge: LLM, completion: completion_replying("auto"))

      assert verdict.tier == :auto
      refute Map.has_key?(verdict, :judge_tier)
    end
  end

  describe "run-level behavioral context" do
    test "run_behavioral findings are rendered into the LLM prompt as context" do
      completion = fn prompt ->
        send(self(), {:prompt, prompt})
        {:ok, ~s({"tier":"review","blast_radius":"x","risks":[],"confidence":0.5})}
      end

      behavioral = [
        %{
          severity: :serious,
          rule: :ecto_query_analysis,
          message: "N+1 in orders",
          source: :telemetry,
          events: []
        }
      ]

      Judge.verdict(block_change(), judge: LLM, completion: completion, run_behavioral: behavioral)

      assert_received {:prompt, prompt}
      assert prompt =~ "N+1 in orders"
      assert prompt =~ "not attributed"
    end
  end
end
