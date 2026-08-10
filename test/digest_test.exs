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
end
