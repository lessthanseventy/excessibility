defmodule Excessibility.Review.Judge.Heuristic do
  @moduledoc """
  Default judge: a transparent, dependency-free verdict derived directly
  from the change. The tier is the change's own tier; each newly-introduced
  finding becomes a risk. No model is consulted, so `confidence` is `nil`.
  """

  @behaviour Excessibility.Review.Judge

  alias Excessibility.Review

  @impl true
  def judge(change, _opts) do
    behavioral = Map.get(change, :behavioral, [])
    all = change.findings ++ behavioral

    %{
      # Recompute so behavioral findings attached after review_pair (e.g. the
      # run-level timeline) are reflected in the tier.
      tier: Review.tier(all),
      blast_radius: blast_radius(change, behavioral),
      risks: Enum.map(all, &risk/1),
      confidence: nil,
      source: :heuristic
    }
  end

  defp blast_radius(change, behavioral) do
    "#{change.region_count} region(s) changed; #{length(change.findings)} a11y finding(s); " <>
      "#{length(behavioral)} behavioral finding(s)"
  end

  defp risk(finding) do
    %{severity: to_string(finding.severity), area: area(finding), detail: finding.message}
  end

  defp area(finding) do
    Map.get(finding, :selector) || to_string(finding.rule)
  end
end
