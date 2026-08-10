defmodule Mix.Tasks.Excessibility.Digest.Compare do
  @shortdoc "Structurally compares two digest.json artifacts"

  @moduledoc """
  Structurally compare two `digest.json` runtime-evidence artifacts.

  Reads a `base` and a `head` `digest.json` (as produced by
  `mix excessibility.debug`) and reports the structural delta between them:
  query fingerprints added/removed/count-changed, plan changes, assign
  `term_bytes` deltas, and coverage notes (views/callbacks observed plus
  measurement-scope differences).

  This task reports evidence only. It emits **no merge verdict and no severity
  beyond advisory**, and it **always exits 0** so it can never fail CI. Treat it
  as a supplemental, human/AI-readable diff of runtime evidence — not a gate.

  ## Usage

      # Human-readable markdown (default)
      $ mix excessibility.digest.compare --base base/digest.json --head head/digest.json

      # Machine-readable JSON
      $ mix excessibility.digest.compare --base base/digest.json --head head/digest.json --format json

  ## Options

  - `--base PATH` - Path to the baseline `digest.json` (required)
  - `--head PATH` - Path to the candidate `digest.json` (required)
  - `--format markdown|json` - Output format (default: `markdown`)

  Because a change in *what was measured* is never reported as a regression,
  when the two digests measured different signals (e.g. one had Ecto configured
  and the other did not) the difference is surfaced as a coverage note rather
  than a fabricated query/assign change.
  """

  use Mix.Task

  alias Excessibility.DigestCompare

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [base: :string, head: :string, format: :string])

    base_path = opts[:base]
    head_path = opts[:head]
    format = opts[:format] || "markdown"

    cond do
      is_nil(base_path) or is_nil(head_path) ->
        usage_error("Both --base and --head are required.")

      not File.exists?(base_path) ->
        usage_error("--base file not found: #{base_path}")

      not File.exists?(head_path) ->
        usage_error("--head file not found: #{head_path}")

      true ->
        base = load(base_path)
        head = load(head_path)
        diff = DigestCompare.diff(base, head)

        diff
        |> render(format)
        |> Mix.shell().info()

        :ok
    end
  end

  defp load(path), do: path |> File.read!() |> Jason.decode!(keys: :atoms)

  defp usage_error(message) do
    Mix.shell().error("""
    #{message}

    Usage:
      mix excessibility.digest.compare --base BASE_DIGEST --head HEAD_DIGEST [--format markdown|json]
    """)

    exit({:shutdown, 1})
  end

  # --- rendering ------------------------------------------------------------

  defp render(diff, "json") do
    diff
    |> jsonify()
    |> Jason.encode!(pretty: true)
  end

  defp render(diff, _markdown), do: markdown(diff)

  # `DigestCompare` output embeds `{view, callback}` tuples (notably in
  # `coverage.callbacks_added/removed`). Jason cannot encode tuples, so walk the
  # whole diff and turn every tuple into a JSON-safe list first.
  defp jsonify(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, jsonify(value)} end)
  end

  defp jsonify(list) when is_list(list), do: Enum.map(list, &jsonify/1)

  defp jsonify(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(&jsonify/1)
  end

  defp jsonify(other), do: other

  defp markdown(diff) do
    Enum.join(
      [
        "# Digest Comparison",
        "",
        coverage_section(diff[:coverage] || %{}),
        queries_section(diff[:queries] || []),
        plans_section(diff[:plans] || []),
        assigns_section(diff[:assigns] || [])
      ],
      "\n"
    )
  end

  defp coverage_section(coverage) do
    notes = coverage[:notes] || []
    views_added = coverage[:views_added] || []
    views_removed = coverage[:views_removed] || []
    callbacks_added = coverage[:callbacks_added] || []
    callbacks_removed = coverage[:callbacks_removed] || []

    Enum.join(
      [
        "## Coverage",
        "",
        "Notes:",
        bullet_list(notes),
        "",
        "Views added: #{inline_list(views_added)}",
        "Views removed: #{inline_list(views_removed)}",
        "Callbacks added: #{inline_list(Enum.map(callbacks_added, &callback_label/1))}",
        "Callbacks removed: #{inline_list(Enum.map(callbacks_removed, &callback_label/1))}",
        ""
      ],
      "\n"
    )
  end

  defp queries_section([]), do: "## Queries\n\nnone\n"

  defp queries_section(queries) do
    body =
      Enum.map_join(queries, "\n", fn q ->
        Enum.join(
          [
            "### #{q[:view]} #{q[:callback]}",
            "Fingerprints added:",
            bullet_list(q[:fingerprints_added] || []),
            "Fingerprints removed:",
            bullet_list(q[:fingerprints_removed] || []),
            "Count changed:",
            count_changed_list(q[:count_changed] || []),
            ""
          ],
          "\n"
        )
      end)

    "## Queries\n\n" <> body
  end

  defp plans_section([]), do: "## Plans\n\nnone\n"

  defp plans_section(plans) do
    body =
      Enum.map_join(plans, "\n", fn p ->
        rows =
          case p[:estimated_rows_delta] do
            nil -> ""
            delta -> " (estimated_rows delta #{signed(delta)})"
          end

        "- #{p[:view]} #{p[:callback]} #{p[:fingerprint]}: plan #{p[:base_plan]} -> #{p[:head_plan]}#{rows}"
      end)

    "## Plans\n\n" <> body <> "\n"
  end

  defp assigns_section([]), do: "## Assigns\n\nnone\n"

  defp assigns_section(assigns) do
    body =
      Enum.map_join(assigns, "\n", fn a ->
        "- #{a[:view]} #{a[:callback]} #{a[:name]}: #{a[:base_term_bytes]} -> #{a[:head_term_bytes]} bytes (delta #{signed(a[:delta_bytes])}), cardinality #{inspect_or_dash(a[:base_cardinality])} -> #{inspect_or_dash(a[:head_cardinality])}"
      end)

    "## Assigns\n\n" <> body <> "\n"
  end

  defp count_changed_list([]), do: "none"

  defp count_changed_list(changes) do
    Enum.map_join(changes, "\n", fn c -> "- #{c[:fingerprint]}: #{c[:base_count]} -> #{c[:head_count]}" end)
  end

  defp callback_label({view, callback}), do: "#{view} #{callback}"
  defp callback_label(other), do: to_string(other)

  defp bullet_list([]), do: "- none"

  defp bullet_list(items) do
    Enum.map_join(items, "\n", &"- #{&1}")
  end

  defp inline_list([]), do: "none"
  defp inline_list(items), do: Enum.join(items, ", ")

  defp signed(n) when is_number(n) and n >= 0, do: "+#{n}"
  defp signed(n), do: to_string(n)

  defp inspect_or_dash(nil), do: "-"
  defp inspect_or_dash(value), do: to_string(value)
end
