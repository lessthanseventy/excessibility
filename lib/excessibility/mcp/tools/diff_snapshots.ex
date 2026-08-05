defmodule Excessibility.MCP.Tools.DiffSnapshots do
  @moduledoc """
  MCP tool: diff two rendered HTML states and report what changed and
  whether the change introduced accessibility regressions.

  Lets an agent that just edited a LiveView ask *"did I change rendered
  behavior I didn't intend?"* It returns the changed regions plus any
  newly-introduced accessibility findings — content that updated without an
  `aria-live` announcement, a control made keyboard-inaccessible, and so on
  — and a risk tier (`auto`/`review`/`block`). Backed by
  `Excessibility.Review`.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.Review

  @impl true
  def name, do: "diff_snapshots"

  @impl true
  def description do
    "Diff two rendered HTML states (before/after) and report what changed and " <>
      "whether it introduced accessibility regressions (e.g. content updated without " <>
      "aria-live, or a control made keyboard-inaccessible). Use after editing a " <>
      "LiveView to confirm you didn't change rendered behavior unintentionally."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "before" => %{"type" => "string", "description" => "Rendered HTML before the change"},
        "after" => %{"type" => "string", "description" => "Rendered HTML after the change"},
        "view" => %{"type" => "string", "description" => "Optional label for the view diffed"}
      },
      "required" => ["before", "after"]
    }
  end

  @impl true
  def execute(%{"before" => before, "after" => current} = args, _opts) when is_binary(before) and is_binary(current) do
    # Before/after here are the same view re-rendered around the agent's own
    # edit, so both sides share fixture data and the content diff is sound —
    # unlike `mix excessibility.review`, where it is opt-in.
    change = Review.review_pair(Map.get(args, "view", "diff"), before, current, content_diff: true)

    {:ok,
     %{
       "status" => "success",
       "view" => change.view,
       "tier" => Atom.to_string(change.tier),
       "regions_changed" => change.region_count,
       "regions" => Enum.map(change.regions, &region/1),
       "findings" => Enum.map(change.findings, &finding/1),
       "warnings" => change.warnings
     }}
  end

  def execute(_args, _opts) do
    {:error, "Missing required arguments: before and after (HTML strings)"}
  end

  defp region(region) do
    %{
      "selector" => region.selector,
      "change" => Atom.to_string(region.change),
      "announced" => region.announced,
      "old_text" => region.old_text,
      "new_text" => region.new_text
    }
  end

  defp finding(finding) do
    %{
      # axe rule ids are strings, LiveView rule ids are atoms
      "rule" => to_string(finding.rule),
      "severity" => Atom.to_string(finding.severity),
      "selector" => finding.selector,
      "message" => finding.message
    }
  end
end
