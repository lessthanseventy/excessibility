defmodule Excessibility.Review.Judge do
  @moduledoc """
  Turns a `Excessibility.Review` change into a release-risk **verdict**.

  A judge takes one view's change (regions + newly-introduced findings) and
  returns a tier, a human-readable blast-radius summary, and structured
  risks. Two judges ship:

    * `Excessibility.Review.Judge.Heuristic` (default) — transparent, no
      dependencies; derives the verdict from the change's findings.
    * `Excessibility.Review.Judge.LLM` — asks a model to reason about the
      change. excessibility owns the prompt, schema, and parsing; the host
      app supplies the actual model call (a `completion` function), so the
      library takes on no HTTP dependency.

  Select a judge per call (`judge: MyJudge`) or globally:

      config :excessibility, review_judge: Excessibility.Review.Judge.LLM

  ## Verdict shape

      %{
        tier: :auto | :review | :block,
        blast_radius: String.t(),
        risks: [%{severity: String.t(), area: String.t(), detail: String.t()}],
        confidence: float() | nil,
        source: :heuristic | :llm
      }
  """

  alias Excessibility.Review.Judge.Heuristic

  @type verdict :: %{
          tier: Excessibility.Review.tier(),
          blast_radius: String.t(),
          risks: [%{severity: String.t(), area: String.t(), detail: String.t()}],
          confidence: float() | nil,
          source: :heuristic | :llm
        }

  @callback judge(change :: Excessibility.Review.change(), opts :: keyword()) :: verdict()

  @doc """
  Judge a change with the configured (or explicitly given) judge.

  Resolution order: `opts[:judge]`, then `config :excessibility, :review_judge`,
  then `Heuristic`.
  """
  @spec verdict(Excessibility.Review.change(), keyword()) :: verdict()
  def verdict(change, opts \\ []) do
    judge =
      Keyword.get(opts, :judge) ||
        Application.get_env(:excessibility, :review_judge, Heuristic)

    judge.judge(change, opts)
  end
end
