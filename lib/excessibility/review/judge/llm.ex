defmodule Excessibility.Review.Judge.LLM do
  @moduledoc """
  A judge that asks a model to reason about a change's blast radius.

  excessibility owns the prompt, the response schema, and the parsing; the
  host application supplies the model call as a `completion` function so the
  library adds no HTTP dependency:

      completion = fn prompt ->
        # call Claude (or any model) with `prompt`, return its text
        {:ok, response_text}
      end

      Excessibility.Review.Judge.LLM.judge(change, completion: completion)

  The function is resolved from `opts[:completion]` or
  `config :excessibility, :review_judge_completion`. If none is configured,
  or the call errors, or the output can't be parsed, this falls back to
  `Excessibility.Review.Judge.Heuristic` — a missing/flaky model never
  crashes a review.

  The model is asked to reply with JSON:

      {"tier":"auto|review|block","blast_radius":"...",
       "risks":[{"severity":"...","area":"...","detail":"..."}],
       "confidence":0.0}
  """

  @behaviour Excessibility.Review.Judge

  alias Excessibility.Review.Judge.Heuristic

  @impl true
  def judge(change, opts) do
    case completion_fn(opts) do
      nil -> Heuristic.judge(change, opts)
      fun -> run(change, fun, opts)
    end
  end

  defp completion_fn(opts) do
    Keyword.get(opts, :completion) ||
      Application.get_env(:excessibility, :review_judge_completion)
  end

  defp run(change, fun, opts) do
    with {:ok, text} <- fun.(build_prompt(change)),
         {:ok, verdict} <- parse(text, change) do
      verdict
    else
      _ -> Heuristic.judge(change, opts)
    end
  end

  defp parse(text, change) do
    with {:ok, %{} = data} <- Jason.decode(text) do
      {:ok,
       %{
         tier: parse_tier(data["tier"], change.tier),
         blast_radius: data["blast_radius"] || "",
         risks: parse_risks(data["risks"]),
         confidence: data["confidence"],
         source: :llm
       }}
    end
  end

  defp parse_tier("auto", _fallback), do: :auto
  defp parse_tier("review", _fallback), do: :review
  defp parse_tier("block", _fallback), do: :block
  defp parse_tier(_other, fallback), do: fallback

  defp parse_risks(risks) when is_list(risks) do
    Enum.map(risks, fn risk ->
      %{severity: risk["severity"], area: risk["area"], detail: risk["detail"]}
    end)
  end

  defp parse_risks(_), do: []

  defp build_prompt(change) do
    """
    You are a release-risk judge for a Phoenix/LiveView change. Decide whether
    this view's change is safe to auto-merge given a strong test + painless
    rollback safety net. Bias toward "auto" when rendering changed but nothing
    accessibility-relevant broke; reserve "block" for new critical issues in
    money / auth / data paths.

    Reply with ONLY this JSON, no prose:
    {"tier":"auto|review|block","blast_radius":"one sentence",
     "risks":[{"severity":"...","area":"selector","detail":"..."}],
     "confidence":0.0}

    View: #{change.view}
    Heuristic tier: #{change.tier}

    Changed regions:
    #{render_regions(change.regions)}

    Newly introduced accessibility findings:
    #{render_findings(change.findings)}

    Behavioral findings (from telemetry analyzers — queries, state, renders):
    #{render_behavioral(Map.get(change, :behavioral, []))}
    """
  end

  defp render_behavioral([]), do: "(none)"

  defp render_behavioral(findings) do
    Enum.map_join(findings, "\n", fn finding ->
      "- [#{finding.severity}] #{finding.rule}: #{finding.message}"
    end)
  end

  defp render_regions([]), do: "(none)"

  defp render_regions(regions) do
    Enum.map_join(regions, "\n", fn region ->
      "- #{region.selector}: #{trim(region.old_text)} => #{trim(region.new_text)}"
    end)
  end

  defp render_findings([]), do: "(none)"

  defp render_findings(findings) do
    Enum.map_join(findings, "\n", fn finding ->
      "- [#{finding.severity}] #{finding.rule} @ #{finding.selector}: #{finding.message}"
    end)
  end

  defp trim(text), do: text |> to_string() |> String.slice(0, 120)
end
