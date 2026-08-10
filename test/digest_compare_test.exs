defmodule Excessibility.DigestCompareTest do
  use ExUnit.Case, async: true

  alias Excessibility.DigestCompare

  # --- fixtures -------------------------------------------------------------

  defp digest(events, opts \\ []) do
    %{
      schema: Keyword.get(opts, :schema, "excessibility.digest/v1"),
      capture: %{
        status: :ok,
        ecto_configured: Keyword.get(opts, :ecto_configured, true),
        enrichers_run: Keyword.get(opts, :enrichers_run, [:ecto_queries, :assign_sizes]),
        plan_capture: Keyword.get(opts, :plan_capture, :disabled),
        timing: :non_comparable,
        capture_version: "0.18.1",
        warnings: []
      },
      coverage: %{
        tests: ["Test"],
        views: events |> Enum.map(& &1.view) |> Enum.uniq(),
        callbacks_observed: events |> Enum.map(& &1.callback) |> Enum.uniq(),
        event_sequence: Enum.map(events, & &1.callback),
        fixtures: %{}
      },
      events: events,
      trajectories: %{}
    }
  end

  defp event(view, callback, opts \\ []) do
    shapes = Keyword.get(opts, :shapes, [])

    %{
      sequence: Keyword.get(opts, :sequence, 1),
      callback: callback,
      view: view,
      queries: %{
        count: shapes |> Enum.map(& &1.count) |> Enum.sum(),
        shapes: shapes,
        repeated: [],
        overflow: nil
      },
      assigns: %{
        total_term_bytes: 0,
        shapes: Keyword.get(opts, :assigns, [])
      }
    }
  end

  defp shape(fp, count, extra \\ %{}) do
    Map.merge(
      %{
        fingerprint: fp,
        operation: "select",
        source: "categories",
        normalized: "n",
        count: count,
        sequences: []
      },
      extra
    )
  end

  defp assign(name, term_bytes, card \\ nil) do
    %{
      name: name,
      kind: if(card, do: "list", else: "scalar"),
      cardinality: card,
      term_bytes: term_bytes,
      path_depth: 1,
      delta_bytes: 0,
      growth: "increased"
    }
  end

  # --- queries --------------------------------------------------------------

  test "new fingerprint in head lands in fingerprints_added" do
    base = digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1)])])

    head =
      digest([
        event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1), shape("sha256:bbb", 1)])
      ])

    result = DigestCompare.diff(base, head)

    assert [q] = result.queries
    assert q.view == "PageLive"
    assert q.callback == "handle_event:save"
    assert q.fingerprints_added == ["sha256:bbb"]
    assert q.fingerprints_removed == []
    assert q.count_changed == []
  end

  test "rising repeat count on a fingerprint lands in count_changed (emerging N+1)" do
    base = digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 3)])])
    head = digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 10)])])

    result = DigestCompare.diff(base, head)

    assert [q] = result.queries
    assert q.fingerprints_added == []
    assert q.count_changed == [%{fingerprint: "sha256:aaa", base_count: 3, head_count: 10}]
  end

  # --- plans ----------------------------------------------------------------

  test "same query fingerprint with different plan fingerprint lands in plans" do
    base =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{
                plan: %{fingerprint: "sha256:plan1", estimated_rows: 100}
              })
            ]
          )
        ],
        plan_capture: :explain
      )

    head =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{
                plan: %{fingerprint: "sha256:plan2", estimated_rows: 500}
              })
            ]
          )
        ],
        plan_capture: :explain
      )

    result = DigestCompare.diff(base, head)

    assert [p] = result.plans
    assert p.fingerprint == "sha256:aaa"
    assert p.base_plan == "sha256:plan1"
    assert p.head_plan == "sha256:plan2"
    assert p.estimated_rows_delta == 400
  end

  test "plan capture mismatch suppresses plans and adds a scope note" do
    base =
      digest(
        [event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1)])],
        plan_capture: :disabled
      )

    head =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{plan: %{fingerprint: "sha256:plan2", estimated_rows: 5}})
            ]
          )
        ],
        plan_capture: :explain
      )

    result = DigestCompare.diff(base, head)

    assert result.plans == []
    assert Enum.any?(result.coverage.notes, &String.contains?(&1, "plan capture differs"))
  end

  # --- assigns --------------------------------------------------------------

  test "assign term_bytes delta is reported" do
    base =
      digest([event("PageLive", "handle_event:save", assigns: [assign("products", 10_000, 50)])])

    head =
      digest([event("PageLive", "handle_event:save", assigns: [assign("products", 18_000, 90)])])

    result = DigestCompare.diff(base, head)

    assert [a] = result.assigns
    assert a.name == "products"
    assert a.base_term_bytes == 10_000
    assert a.head_term_bytes == 18_000
    assert a.delta_bytes == 8_000
    assert a.base_cardinality == 50
    assert a.head_cardinality == 90
  end

  # --- measurement-scope guard ---------------------------------------------

  test "ecto scope mismatch emits coverage note and NO fabricated queries" do
    base =
      digest(
        [event("PageLive", "handle_event:save", shapes: [])],
        ecto_configured: false
      )

    head =
      digest(
        [event("PageLive", "handle_event:save", shapes: [shape("sha256:bbb", 5)])],
        ecto_configured: true
      )

    result = DigestCompare.diff(base, head)

    assert result.queries == []
    assert result.plans == []

    assert Enum.any?(
             result.coverage.notes,
             &String.contains?(&1, "base did not measure queries")
           )
  end

  test "schema-version mismatch adds a prominent note" do
    base = digest([event("PageLive", "mount")], schema: "excessibility.digest/v0")
    head = digest([event("PageLive", "mount")], schema: "excessibility.digest/v1")

    result = DigestCompare.diff(base, head)

    assert Enum.any?(result.coverage.notes, &String.contains?(&1, "schema mismatch"))
  end

  # --- coverage deltas ------------------------------------------------------

  test "added and removed callbacks/views show up in coverage" do
    base = digest([event("PageLive", "mount"), event("PageLive", "handle_event:old")])
    head = digest([event("PageLive", "mount"), event("OtherLive", "handle_event:new")])

    result = DigestCompare.diff(base, head)

    assert {"OtherLive", "handle_event:new"} in result.coverage.callbacks_added
    assert {"PageLive", "handle_event:old"} in result.coverage.callbacks_removed
    assert "OtherLive" in result.coverage.views_added
  end

  # --- determinism ----------------------------------------------------------

  test "diff of the same pair twice is equal" do
    base = digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 3)])])
    head = digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 9)])])

    assert DigestCompare.diff(base, head) == DigestCompare.diff(base, head)
  end

  test "input event order does not change output" do
    e1 = event("PageLive", "mount", shapes: [shape("sha256:aaa", 1)])
    e2 = event("PageLive", "handle_event:save", shapes: [shape("sha256:bbb", 2)])
    e3 = event("OtherLive", "mount", assigns: [assign("x", 100)])

    base = digest([e1, e2, e3])
    head = digest([e3, e1, e2])

    forward = DigestCompare.diff(base, base)
    shuffled = DigestCompare.diff(head, head)

    assert forward == shuffled
  end

  # --- key tolerance --------------------------------------------------------

  test "tolerates string-keyed digests (Jason.decode without keys: :atoms)" do
    base = %{
      "schema" => "excessibility.digest/v1",
      "capture" => %{
        "ecto_configured" => true,
        "enrichers_run" => ["ecto_queries", "assign_sizes"],
        "plan_capture" => "disabled"
      },
      "events" => [
        %{
          "view" => "PageLive",
          "callback" => "handle_event:save",
          "queries" => %{"shapes" => [%{"fingerprint" => "sha256:aaa", "count" => 3}]},
          "assigns" => %{"shapes" => []}
        }
      ]
    }

    head = %{
      "schema" => "excessibility.digest/v1",
      "capture" => %{
        "ecto_configured" => true,
        "enrichers_run" => ["ecto_queries", "assign_sizes"],
        "plan_capture" => "disabled"
      },
      "events" => [
        %{
          "view" => "PageLive",
          "callback" => "handle_event:save",
          "queries" => %{
            "shapes" => [
              %{"fingerprint" => "sha256:aaa", "count" => 10},
              %{"fingerprint" => "sha256:bbb", "count" => 1}
            ]
          },
          "assigns" => %{"shapes" => []}
        }
      ]
    }

    result = DigestCompare.diff(base, head)

    assert [q] = result.queries
    assert q.fingerprints_added == ["sha256:bbb"]
    assert q.count_changed == [%{fingerprint: "sha256:aaa", base_count: 3, head_count: 10}]
  end
end
