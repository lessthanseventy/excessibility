defmodule Excessibility.DigestTest do
  use ExUnit.Case, async: true

  alias Excessibility.Digest

  defp timeline do
    %{
      test: "PageLiveTest: saves",
      timeline: [
        %{sequence: 1, event: "mount", view_module: "PageLive", ecto_queries: [], assign_sizes: %{}},
        %{
          sequence: 2,
          event: "handle_event:save",
          view_module: "PageLive",
          ecto_queries:
            List.duplicate(
              %{
                operation: :select,
                source: "categories",
                fingerprint: "sha256:aaa",
                normalized: "select … where id = $?",
                duration_ms: 1.0,
                query: "SELECT ..."
              },
              10
            ),
          assign_sizes: %{"products" => 18_000},
          total_memory: 18_000,
          list_sizes: %{"products" => 50}
        }
      ]
    }
  end

  test "emits versioned schema and value-free query shapes with no raw sql" do
    d = Digest.build(timeline(), ecto_configured?: true, enrichers_run: [:ecto_queries, :assign_sizes])
    assert d.schema == "excessibility.digest/v1"
    assert d.capture.status == :ok
    assert d.capture.ecto_configured == true

    ev = Enum.find(d.events, &(&1.callback == "handle_event:save"))
    assert ev.queries.count == 10
    [shape] = ev.queries.shapes
    assert shape.fingerprint == "sha256:aaa"
    assert shape.count == 10
    # NO raw sql anywhere in the digest
    refute Jason.encode!(d) =~ "SELECT ..."
  end

  test "N+1 evidence groups by fingerprint" do
    d = Digest.build(timeline(), ecto_configured?: true)
    ev = Enum.find(d.events, &(&1.callback == "handle_event:save"))
    assert [%{fingerprint: "sha256:aaa", repetitions: 10, severity: :advisory}] = ev.queries.repeated
  end

  test "coverage distinguishes unconfigured from configured-and-clean" do
    d = Digest.build(timeline(), ecto_configured?: false)
    assert d.capture.ecto_configured == false
  end

  # A timeline whose ecto_queries carry a value-free `:plan` surfaces that plan
  # on the query shape (representative's plan; plans are per-fingerprint-stable).
  defp planned_timeline do
    plan = %{fingerprint: "sha256:plan", nodes: ["Seq Scan"], relations: ["categories"]}

    %{
      test: "PageLiveTest: plan",
      timeline: [
        %{
          sequence: 1,
          event: "handle_event:save",
          view_module: "PageLive",
          ecto_queries: [
            %{
              operation: :select,
              source: "categories",
              fingerprint: "sha256:aaa",
              normalized: "select … where id = $?",
              duration_ms: 1.0,
              query: "SELECT ...",
              plan: plan
            }
          ],
          assign_sizes: %{},
          total_memory: 0
        }
      ]
    }
  end

  test "query shape surfaces a value-free plan variant set when present" do
    d = Digest.build(planned_timeline(), ecto_configured?: true)
    ev = Enum.find(d.events, &(&1.callback == "handle_event:save"))
    [shape] = ev.queries.shapes

    assert shape.plans == [
             %{
               fingerprint: "sha256:plan",
               nodes: ["Seq Scan"],
               relations: ["categories"]
             }
           ]

    assert shape.variants_omitted == 0

    # Still value-free: no raw sql leaks even with a plan attached.
    refute Jason.encode!(d) =~ "SELECT ..."
  end

  test "capture.warnings includes plan-capture warnings threaded via opts" do
    d = Digest.build(timeline(), ecto_configured?: true, warnings: ["boom"])
    assert "boom" in d.capture.warnings
  end

  # Three events of the SAME view where `products` term_bytes grows 0 -> 9000 -> 18000.
  defp growing_timeline do
    %{
      test: "PageLiveTest: grows",
      timeline: [
        %{
          sequence: 1,
          event: "mount",
          view_module: "PageLive",
          ecto_queries: [],
          assign_sizes: %{"products" => 0},
          total_memory: 0
        },
        %{
          sequence: 2,
          event: "handle_event:load",
          view_module: "PageLive",
          ecto_queries: [],
          assign_sizes: %{"products" => 9_000},
          total_memory: 9_000,
          list_sizes: %{"products" => 25}
        },
        %{
          sequence: 3,
          event: "handle_event:load_more",
          view_module: "PageLive",
          ecto_queries: [],
          assign_sizes: %{"products" => 18_000},
          total_memory: 18_000,
          list_sizes: %{"products" => 50}
        }
      ]
    }
  end

  test "assign shapes carry names and coarse sizes only, with per-event growth" do
    d = Digest.build(timeline(), ecto_configured?: true)
    ev = Enum.find(d.events, &(&1.callback == "handle_event:save"))
    [a] = ev.assigns.shapes
    assert a.name == "products"
    assert a.kind == "list"
    assert a.cardinality == 50
    assert a.term_bytes == 18_000
    assert a.growth in ["new", "increased", "decreased", "stable", "removed"]
    refute Map.has_key?(a, :value)
  end

  test "scalar assign (no list_sizes) has nil cardinality" do
    tl = %{
      test: "t",
      timeline: [
        %{
          sequence: 1,
          event: "mount",
          view_module: "PageLive",
          ecto_queries: [],
          assign_sizes: %{"count" => 8},
          total_memory: 8
        }
      ]
    }

    d = Digest.build(tl, ecto_configured?: false)
    ev = Enum.find(d.events, &(&1.callback == "mount"))
    [a] = ev.assigns.shapes
    assert a.name == "count"
    assert a.kind == "scalar"
    assert a.cardinality == nil
  end

  test "trajectories flag monotonic growth across events" do
    d = Digest.build(growing_timeline(), ecto_configured?: true)
    assert "products" in d.trajectories["PageLive"].monotonic_growth
  end

  # A timeline whose event carries a malformed `assign_sizes` (a list, not a
  # map) so `assign_block`'s `Enum.map(_, fn {name, bytes} -> ...)` raises,
  # genuinely tripping the crash-isolation rescue.
  defp malformed_timeline do
    %{
      test: "PageLiveTest: malformed",
      timeline: [
        %{
          sequence: 1,
          event: "mount",
          view_module: "PageLive",
          ecto_queries: [],
          assign_sizes: [1, 2, 3]
        }
      ]
    }
  end

  test "failed digest still carries every top-level key including coverage" do
    d = Digest.build(malformed_timeline(), ecto_configured?: true)

    assert d.capture.status == :failed
    assert d.capture.warnings != []

    # All top-level keys present regardless of status.
    assert Map.has_key?(d, :schema)
    assert Map.has_key?(d, :capture)
    assert Map.has_key?(d, :coverage)
    assert Map.has_key?(d, :events)
    assert Map.has_key?(d, :trajectories)

    assert d.schema == "excessibility.digest/v1"
    assert d.events == []
    assert d.trajectories == %{}

    # Coverage has the empty-list shape the schema/compare consumer expects.
    assert d.coverage == %{
             tests: [],
             views: [],
             callbacks_observed: [],
             event_sequence: [],
             fixtures: %{}
           }
  end

  describe "fixture validation (privacy)" do
    test "keeps only string-keyed non-negative integer cardinalities" do
      d = Digest.build(timeline(), fixtures: %{"records" => 2, "orgs" => 0})
      assert d.coverage.fixtures == %{"records" => 2, "orgs" => 0}
      assert d.capture.warnings == []
    end

    test "drops string values and surfaces the rejected key names (not values)" do
      d =
        Digest.build(timeline(),
          fixtures: %{"request_email" => "alice@example.com", "records" => 2}
        )

      assert d.coverage.fixtures == %{"records" => 2}
      # The dropped value must never appear anywhere in the emitted digest.
      refute Jason.encode!(d) =~ "alice@example.com"
      # The rejected key name is surfaced as a value-free warning.
      assert Enum.any?(d.capture.warnings, &(&1 =~ "request_email"))
    end

    test "drops nested maps and lists rather than copying them" do
      d =
        Digest.build(timeline(),
          fixtures: %{
            "nested" => %{"secret" => "s3cr3t"},
            "list" => [1, 2, 3],
            "count" => 5
          }
        )

      assert d.coverage.fixtures == %{"count" => 5}
      refute Jason.encode!(d) =~ "s3cr3t"
    end

    test "drops negative and non-integer numeric cardinalities" do
      d = Digest.build(timeline(), fixtures: %{"neg" => -1, "float" => 2.5, "ok" => 3})
      assert d.coverage.fixtures == %{"ok" => 3}
    end

    test "atom keys from config :fixtures are normalized to strings and validated" do
      d = Digest.build(timeline(), fixtures: %{records: 4, leaky: "value"})
      assert d.coverage.fixtures == %{"records" => 4}
      refute Jason.encode!(d) =~ "\"value\""
    end

    test "a non-map fixtures value is ignored with a warning" do
      d = Digest.build(timeline(), fixtures: "not a map")
      assert d.coverage.fixtures == %{}
      assert Enum.any?(d.capture.warnings, &(&1 =~ "fixtures"))
    end
  end

  # A module-atom view (as live capture produces) must be rendered without the
  # `Elixir.` prefix everywhere it becomes an output field.
  defp atom_view_timeline do
    %{
      test: "PageLiveTest: atom view",
      timeline: [
        %{
          sequence: 1,
          event: "mount",
          view_module: SomeApp.PageLive,
          ecto_queries: [],
          assign_sizes: %{"count" => 8},
          total_memory: 8
        }
      ]
    }
  end

  test "module-atom view names are stripped of the Elixir. prefix" do
    d = Digest.build(atom_view_timeline(), ecto_configured?: false)

    ev = Enum.find(d.events, &(&1.callback == "mount"))
    assert ev.view == "SomeApp.PageLive"
    assert "SomeApp.PageLive" in d.coverage.views
    assert Map.has_key?(d.trajectories, "SomeApp.PageLive")

    refute Jason.encode!(d) =~ "Elixir."
  end
end
