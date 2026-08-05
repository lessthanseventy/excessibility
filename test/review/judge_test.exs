defmodule Excessibility.Review.JudgeTest do
  use ExUnit.Case, async: true

  alias Excessibility.Review
  alias Excessibility.Review.Judge
  alias Excessibility.Review.Judge.Heuristic
  alias Excessibility.Review.Judge.LLM

  # A change that introduces a serious (keyboard-inaccessible) violation.
  defp block_change do
    Review.review_pair("editor", "<div>Save</div>", ~s(<div phx-click="save">Save</div>))
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

  describe "verdict/2 dispatch" do
    test "defaults to the heuristic judge" do
      assert Judge.verdict(block_change()).source == :heuristic
    end

    test "honors an explicit :judge module" do
      assert Judge.verdict(block_change(), judge: LLM, completion: fn _ -> {:error, :x} end).source ==
               :heuristic
    end
  end
end
