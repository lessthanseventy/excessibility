defmodule Excessibility.Review.Judge.Heuristic do
  @moduledoc """
  Default judge: a transparent, dependency-free verdict derived directly
  from the change. The tier is the change's own tier; each newly-introduced
  finding becomes a risk. No model is consulted, so `confidence` is `nil`.
  """

  @behaviour Excessibility.Review.Judge

  @impl true
  def judge(change, _opts) do
    %{
      tier: change.tier,
      blast_radius: blast_radius(change),
      risks: Enum.map(change.findings, &risk/1),
      confidence: nil,
      source: :heuristic
    }
  end

  defp blast_radius(change) do
    "#{change.region_count} region(s) changed; #{length(change.findings)} new finding(s)"
  end

  defp risk(finding) do
    %{severity: to_string(finding.severity), area: finding.selector, detail: finding.message}
  end
end
