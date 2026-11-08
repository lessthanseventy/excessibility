defmodule Excessibility.DigestCompare.Notes do
  @moduledoc """
  Coverage notes for `Excessibility.DigestCompare`: each names a difference in
  what the two sides measured, so a scope change never reads as a regression.
  """

  # Measurement-scope notes: each describes a *difference in what was measured*,
  # so a scope change is never mistaken for a regression. Sorted + deduped for
  # determinism.
  def notes(base, head, omission) do
    []
    |> status_note(base, head)
    |> non_digest_note(base, head)
    |> schema_note(base, head)
    |> ecto_note(base, head)
    |> plan_note(base, head)
    |> omission_note(omission)
    |> enricher_note(base, head)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A failed/partial capture yields empty events, so every delta below is a
  # measurement artifact rather than a real change. Surface that prominently
  # for either side.
  defp status_note(notes, base, head) do
    notes
    |> maybe_status_note(head.status, "head")
    |> maybe_status_note(base.status, "base")
  end

  defp maybe_status_note(notes, "ok", _side), do: notes

  defp maybe_status_note(notes, status, side) do
    [
      "#{side} capture did not complete (status: #{status}) — coverage/query deltas below are unreliable"
      | notes
    ]
  end

  # Valid JSON that is not a digest (no events on either side) produces no
  # meaningful structural deltas; flag it so the empty result is not read as
  # "no changes".
  defp non_digest_note(notes, base, head) do
    if not base.has_events? and not head.has_events? do
      ["input does not look like an excessibility digest (no events)" | notes]
    else
      notes
    end
  end

  defp schema_note(notes, base, head) do
    if base.schema == head.schema do
      notes
    else
      ["schema mismatch (base: #{base.schema}, head: #{head.schema})" | notes]
    end
  end

  defp ecto_note(notes, base, head) do
    cond do
      base.ecto_configured == head.ecto_configured ->
        notes

      not base.ecto_configured ->
        ["base did not measure queries (ecto not configured)" | notes]

      true ->
        ["head did not measure queries (ecto not configured)" | notes]
    end
  end

  defp plan_note(notes, base, head) do
    if base.ecto_configured and head.ecto_configured and base.plan_capture != head.plan_capture do
      ["plan capture differs (base: #{base.plan_capture}, head: #{head.plan_capture})" | notes]
    else
      notes
    end
  end

  # The digest bounds each SQL fingerprint's plan-variant set, so a side can drop
  # structures it never emitted. A bounded comparison that cannot see a structure
  # must not stay silent about it — surface per-side counts and state plainly that
  # those variants were never compared. Only meaningful when plans
  # were actually comparable; otherwise the scope difference is already noted.
  defp omission_note(notes, %{comparable?: false}), do: notes
  defp omission_note(notes, %{base: 0, head: 0}), do: notes

  defp omission_note(notes, %{base: base, head: head}) do
    notes
    |> maybe_omission_note(head, "head")
    |> maybe_omission_note(base, "base")
  end

  defp maybe_omission_note(notes, 0, _side), do: notes

  defp maybe_omission_note(notes, count, side) do
    [
      "#{side} omitted #{count} bounded plan variant(s) that were not compared (digest bound)"
      | notes
    ]
  end

  defp enricher_note(notes, base, head) do
    base_only = base.enrichers |> MapSet.difference(head.enrichers) |> Enum.sort()
    head_only = head.enrichers |> MapSet.difference(base.enrichers) |> Enum.sort()

    if base_only == [] and head_only == [] do
      notes
    else
      [
        "enrichers differ (base only: #{fmt_list(base_only)}; head only: #{fmt_list(head_only)})"
        | notes
      ]
    end
  end

  defp fmt_list([]), do: "none"
  defp fmt_list(list), do: Enum.join(list, ", ")
end
