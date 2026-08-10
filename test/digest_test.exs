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
end
