defmodule Excessibility.DigestCompareTest do
  use ExUnit.Case, async: true

  alias Excessibility.DigestCompare
  alias Excessibility.QueryEvidence
  alias Excessibility.QueryPlan

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
    # A single structure changed shape: the old one is removed, the new added.
    assert p.variants_removed == ["sha256:plan1"]
    assert p.variants_added == ["sha256:plan2"]
    assert p.variant_deltas == []
  end

  test "stable plan fingerprint with changed actual rows still produces a plan delta (#157)" do
    base =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{
                plan: %{fingerprint: "sha256:plan", estimated_rows: 1, actual_rows: 1}
              })
            ]
          )
        ],
        plan_capture: :explain_analyze
      )

    head =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{
                plan: %{fingerprint: "sha256:plan", estimated_rows: 1, actual_rows: 10_000}
              })
            ]
          )
        ],
        plan_capture: :explain_analyze
      )

    result = DigestCompare.diff(base, head)

    assert [p] = result.plans
    assert p.fingerprint == "sha256:aaa"
    # Structural shape is unchanged (no added/removed variants); the change is
    # purely numeric, reported against the shared variant.
    assert p.variants_added == []
    assert p.variants_removed == []
    assert [d] = p.variant_deltas
    assert d.plan == "sha256:plan"
    assert d.actual_rows_delta == 9_999
    assert d.estimated_rows_delta == 0
  end

  test "node-level actual-row change under a stable fingerprint surfaces as a node delta (#157)" do
    plan = fn child_actual ->
      %{
        fingerprint: "sha256:plan",
        estimated_rows: 1,
        actual_rows: 1,
        node_rows: [
          %{
            node: "Nested Loop",
            relation: nil,
            depth: 0,
            estimated_rows: 1,
            actual_rows: 1,
            loops: 1,
            rows_touched: 1,
            estimate_error: 0.0
          },
          %{
            node: "Seq Scan",
            relation: "children",
            depth: 1,
            estimated_rows: 50,
            actual_rows: child_actual,
            loops: 1,
            rows_touched: child_actual,
            estimate_error: nil
          }
        ]
      }
    end

    base =
      digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1, %{plan: plan.(10)})])],
        plan_capture: :explain_analyze
      )

    head =
      digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1, %{plan: plan.(10_000)})])],
        plan_capture: :explain_analyze
      )

    result = DigestCompare.diff(base, head)

    assert [p] = result.plans
    assert p.variants_added == []
    assert p.variants_removed == []
    assert [d] = p.variant_deltas
    assert d.plan == "sha256:plan"
    assert [node] = d.node_deltas
    assert node.relation == "children"
    assert node.depth == 1
    assert node.actual_rows_delta == 9_990
    assert node.rows_touched_delta == 9_990
  end

  test "later same-fingerprint occurrence that grows produces a plan delta end-to-end (#167)" do
    # An EXPLAIN ANALYZE plan whose child Seq Scan touches `child_actual` rows.
    explain = fn child_actual ->
      [
        %{
          "Plan" => %{
            "Node Type" => "Nested Loop",
            "Plan Rows" => 1,
            "Actual Rows" => 1,
            "Actual Loops" => 1,
            "Plans" => [
              %{
                "Node Type" => "Index Scan",
                "Relation Name" => "parents",
                "Plan Rows" => 1,
                "Actual Rows" => 1,
                "Actual Loops" => 1
              },
              %{
                "Node Type" => "Seq Scan",
                "Relation Name" => "children",
                "Plan Rows" => 1,
                "Actual Rows" => child_actual,
                "Actual Loops" => 1
              }
            ]
          }
        }
      ]
    end

    # Emit exactly as Digest does: two occurrences of one query fingerprint in a
    # single event — the FIRST cheap (touches 1) and a LATER one heavier. The
    # first occurrence is identical between base and head; only the later one
    # grows. Aggregation must surface that growth as a node-level delta.
    emit = fn later_touched ->
      record = fn plan ->
        %{operation: :select, source: "children", fingerprint: "sha256:aaa", normalized: "n", plan: plan}
      end

      QueryEvidence.shapes([
        record.(QueryPlan.summarize(explain.(1))),
        record.(QueryPlan.summarize(explain.(later_touched)))
      ])
    end

    base =
      digest([event("PageLive", "handle_event:save", shapes: emit.(10_000))], plan_capture: :explain_analyze)

    head =
      digest([event("PageLive", "handle_event:save", shapes: emit.(20_000))], plan_capture: :explain_analyze)

    result = DigestCompare.diff(base, head)

    assert [p] = result.plans
    assert p.variants_added == []
    assert p.variants_removed == []
    assert [d] = p.variant_deltas
    assert node = Enum.find(d.node_deltas, &(&1.relation == "children"))
    assert node.rows_touched_delta == 10_000
  end

  test "identical plans produce no plan delta" do
    plan = %{fingerprint: "sha256:plan", estimated_rows: 1, actual_rows: 1, node_rows: []}

    base =
      digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1, %{plan: plan})])],
        plan_capture: :explain_analyze
      )

    head =
      digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1, %{plan: plan})])],
        plan_capture: :explain_analyze
      )

    assert DigestCompare.diff(base, head).plans == []
  end

  test "a changed non-dominant plan variant is reported even when a heavier variant is unchanged (#173)" do
    heavy = %{fingerprint: "sha256:A", estimated_rows: 10_000, node_rows: []}
    light_b = %{fingerprint: "sha256:B", estimated_rows: 5, node_rows: []}
    light_c = %{fingerprint: "sha256:C", estimated_rows: 5, node_rows: []}

    # One SQL fingerprint carrying two distinct structures per side; counts equal.
    # base = {heavy A, light B}; head = {same heavy A, changed light C}.
    base =
      digest(
        [event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 2, %{plans: [heavy, light_b]})])],
        plan_capture: :explain
      )

    head =
      digest(
        [event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 2, %{plans: [heavy, light_c]})])],
        plan_capture: :explain
      )

    result = DigestCompare.diff(base, head)

    assert [p] = result.plans
    assert p.fingerprint == "sha256:aaa"
    # The secondary path changed structure B -> C; the dominant path A must not
    # mask it. The previous single-representative aggregate reported nothing here.
    assert p.variants_removed == ["sha256:B"]
    assert p.variants_added == ["sha256:C"]
    # Heavy A is byte-identical on both sides, so it contributes no delta.
    assert p.variant_deltas == []
  end

  test "a bound-omitted plan variant that changed is surfaced, never read as equal (#183)" do
    # Both sides capture 9 distinct structural variants under one SQL fingerprint.
    # Eight are identical; the ninth differs and is exactly the one the bound
    # (@max_plan_variants == 8) drops. The retained sets match, so without the
    # omission signal the comparison would report nothing at all.
    variant = fn fp -> %{fingerprint: "sha256:#{fp}", estimated_rows: 5, node_rows: []} end
    query = fn plan -> %{operation: :select, source: "t", fingerprint: "sha256:aaa", normalized: "n", plan: plan} end
    retained = for i <- 0..7, do: variant.("a#{i}")

    [base_shape] = QueryEvidence.shapes(Enum.map(retained ++ [variant.("zbase")], query))
    [head_shape] = QueryEvidence.shapes(Enum.map(retained ++ [variant.("zhead")], query))

    assert base_shape.variants_omitted == 1
    assert head_shape.variants_omitted == 1

    base = digest([event("PageLive", "handle_event:save", shapes: [base_shape])], plan_capture: :explain)
    head = digest([event("PageLive", "handle_event:save", shapes: [head_shape])], plan_capture: :explain)

    result = DigestCompare.diff(base, head)

    # A forced plans entry carries the per-side omission counts even though the
    # retained variant sets are identical.
    assert [p] = result.plans
    assert p.fingerprint == "sha256:aaa"
    assert p.variants_added == []
    assert p.variants_removed == []
    assert p.variant_deltas == []
    assert p.base_variants_omitted == 1
    assert p.head_variants_omitted == 1

    # And the incompleteness is stated in coverage, so an empty-looking entry is
    # never read as a clean result.
    assert Enum.any?(result.coverage.notes, &String.contains?(&1, "omitted"))
  end

  test "a bound-omitted variant on a query present on only one side is surfaced as a coverage note (#183)" do
    # `plan_diffs/3` only iterates the intersection of SQL fingerprints, so a
    # fingerprint present on just one side never reaches a plans entry. Its
    # omission must still surface via coverage.
    base =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{plans: [%{fingerprint: "sha256:p", estimated_rows: 5, node_rows: []}]}),
              shape("sha256:only", 1, %{
                plans: [%{fingerprint: "sha256:q", estimated_rows: 5, node_rows: []}],
                variants_omitted: 2
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
            shapes: [shape("sha256:aaa", 1, %{plans: [%{fingerprint: "sha256:p", estimated_rows: 5, node_rows: []}]})]
          )
        ],
        plan_capture: :explain
      )

    result = DigestCompare.diff(base, head)

    # No shared-fingerprint plan omission to force an entry for...
    assert Enum.all?(result.plans, &(&1.base_variants_omitted == 0 and &1.head_variants_omitted == 0))
    # ...but base's extra fingerprint dropped two structures, and that is not silent.
    assert Enum.any?(result.coverage.notes, &(String.contains?(&1, "base") and String.contains?(&1, "omitted")))
    assert Enum.any?(result.coverage.notes, &String.contains?(&1, "2"))
  end

  test "plan omission is not noted when plans are not comparable (#183)" do
    # If plan capture modes differ, plans are suppressed and the scope difference
    # is already noted; an omission note would be misleading noise.
    base =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{
                plans: [%{fingerprint: "sha256:p", estimated_rows: 5, node_rows: []}],
                variants_omitted: 3
              })
            ]
          )
        ],
        plan_capture: :explain
      )

    head =
      digest(
        [event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1)])],
        plan_capture: :disabled
      )

    result = DigestCompare.diff(base, head)

    assert result.plans == []
    refute Enum.any?(result.coverage.notes, &String.contains?(&1, "omitted"))
    assert Enum.any?(result.coverage.notes, &String.contains?(&1, "plan capture differs"))
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

  test "tiny byte-only assign deltas are suppressed by default (#159)" do
    # Two unchanged runs whose per-assign term_bytes jitter by a byte or two
    # with identical cardinality must not produce assign deltas.
    base =
      digest([
        event("PageLive", "handle_event:save", assigns: [assign("a", 1_000, 5), assign("b", 2_000, nil)])
      ])

    head =
      digest([
        event("PageLive", "handle_event:save", assigns: [assign("a", 1_001, 5), assign("b", 1_998, nil)])
      ])

    assert DigestCompare.diff(base, head).assigns == []
  end

  test "a cardinality change is never suppressed even with a tiny byte delta (#159)" do
    base = digest([event("PageLive", "handle_event:save", assigns: [assign("items", 1_000, 5)])])
    head = digest([event("PageLive", "handle_event:save", assigns: [assign("items", 1_001, 6)])])

    assert [a] = DigestCompare.diff(base, head).assigns
    assert a.name == "items"
    assert a.base_cardinality == 5
    assert a.head_cardinality == 6
  end

  test "a large byte-only delta is still reported (#159)" do
    base = digest([event("PageLive", "handle_event:save", assigns: [assign("blob", 1_000, nil)])])
    head = digest([event("PageLive", "handle_event:save", assigns: [assign("blob", 20_000, nil)])])

    assert [a] = DigestCompare.diff(base, head).assigns
    assert a.delta_bytes == 19_000
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

  # --- C1: failed/partial capture must not masquerade as a regression -------

  test "failed head capture adds a prominent status note (C1)" do
    base = digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1)])])

    head = %{
      schema: "excessibility.digest/v1",
      capture: %{
        status: :failed,
        ecto_configured: true,
        enrichers_run: [:ecto_queries, :assign_sizes],
        plan_capture: :disabled
      },
      coverage: %{views: [], callbacks_observed: []},
      events: []
    }

    result = DigestCompare.diff(base, head)

    # The note must be present and clearly flag the deltas as unreliable.
    assert Enum.any?(
             result.coverage.notes,
             &String.contains?(&1, "head capture did not complete")
           )

    # Structural deltas are still emitted (not suppressed) — but now annotated.
    assert {"PageLive", "handle_event:save"} in result.coverage.callbacks_removed
  end

  test "failed base capture adds a prominent status note (C1)" do
    base = %{
      schema: "excessibility.digest/v1",
      capture: %{status: "failed", ecto_configured: true, plan_capture: "disabled"},
      events: []
    }

    head = digest([event("PageLive", "handle_event:save", shapes: [shape("sha256:aaa", 1)])])

    result = DigestCompare.diff(base, head)

    assert Enum.any?(
             result.coverage.notes,
             &String.contains?(&1, "base capture did not complete")
           )
  end

  # --- I2: plan aggregation must be order-independent -----------------------

  test "plan merge is order-independent for same fp with different plans (I2)" do
    base =
      digest(
        [
          event("PageLive", "handle_event:save",
            shapes: [
              shape("sha256:aaa", 1, %{plan: %{fingerprint: "sha256:plan0", estimated_rows: 1}})
            ]
          )
        ],
        plan_capture: :explain
      )

    e_plan1 =
      event("PageLive", "handle_event:save",
        shapes: [
          shape("sha256:aaa", 1, %{plan: %{fingerprint: "sha256:plan1", estimated_rows: 100}})
        ]
      )

    e_plan2 =
      event("PageLive", "handle_event:save",
        shapes: [
          shape("sha256:aaa", 1, %{plan: %{fingerprint: "sha256:plan2", estimated_rows: 500}})
        ]
      )

    head_forward = digest([e_plan1, e_plan2], plan_capture: :explain)
    head_reversed = digest([e_plan2, e_plan1], plan_capture: :explain)

    assert DigestCompare.diff(base, head_forward) == DigestCompare.diff(base, head_reversed)
  end

  # --- M4: non-digest input note --------------------------------------------

  test "input without events key gets a not-a-digest coverage note (M4)" do
    base = %{schema: "excessibility.digest/v1", capture: %{status: :ok}}
    head = %{schema: "excessibility.digest/v1", capture: %{status: :ok}}

    result = DigestCompare.diff(base, head)

    assert Enum.any?(
             result.coverage.notes,
             &String.contains?(&1, "does not look like an excessibility digest")
           )
  end
end
