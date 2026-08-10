defmodule Mix.Tasks.Excessibility.Digest.CompareTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Excessibility.Digest.Compare, as: CompareTask

  setup do
    dir = Path.join(System.tmp_dir!(), "excessibility_digest_compare_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    base_path = Path.join(dir, "base_digest.json")
    head_path = Path.join(dir, "head_digest.json")

    File.write!(base_path, Jason.encode!(base_digest()))
    File.write!(head_path, Jason.encode!(head_digest()))

    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir, base_path: base_path, head_path: head_path}
  end

  # base: one SELECT on PageLive/handle_event:save, assign "products" small
  defp base_digest do
    %{
      schema: "excessibility.digest/v1",
      capture: %{
        ecto_configured: true,
        plan_capture: "disabled",
        enrichers_run: ["ecto_queries", "assign_sizes"]
      },
      events: [
        %{
          sequence: 1,
          view: "PageLive",
          callback: "handle_event:save",
          queries: %{
            count: 1,
            shapes: [
              %{fingerprint: "sha256:aaa", count: 1, operation: "select", source: "products"}
            ]
          },
          assigns: %{shapes: [%{name: "products", term_bytes: 1000, cardinality: 10}]}
        }
      ]
    }
  end

  # head: adds a new query fingerprint (sha256:bbb), grows the assign, adds a
  # brand-new callback (tuple in coverage.callbacks_added), and runs an extra
  # enricher (produces a coverage note).
  defp head_digest do
    %{
      schema: "excessibility.digest/v1",
      capture: %{
        ecto_configured: true,
        plan_capture: "disabled",
        enrichers_run: ["ecto_queries", "assign_sizes", "push_events"]
      },
      events: [
        %{
          sequence: 1,
          view: "PageLive",
          callback: "handle_event:save",
          queries: %{
            count: 4,
            shapes: [
              %{fingerprint: "sha256:aaa", count: 1, operation: "select", source: "products"},
              %{fingerprint: "sha256:bbb", count: 3, operation: "select", source: "categories"}
            ]
          },
          assigns: %{shapes: [%{name: "products", term_bytes: 5000, cardinality: 50}]}
        },
        %{
          sequence: 2,
          view: "PageLive",
          callback: "handle_event:delete",
          queries: %{count: 0, shapes: []},
          assigns: %{shapes: []}
        }
      ]
    }
  end

  test "markdown (default) reports the added query fingerprint and a coverage note", ctx do
    output =
      capture_io(fn ->
        assert CompareTask.run(["--base", ctx.base_path, "--head", ctx.head_path]) == :ok
      end)

    # Added query fingerprint surfaces
    assert output =~ "sha256:bbb"
    # Coverage note about the enricher difference
    assert output =~ "enrichers differ"
    assert output =~ "push_events"
    # Section headings present
    assert output =~ "Queries"
    assert output =~ "Assigns"
    # New callback shows up in coverage
    assert output =~ "handle_event:delete"
  end

  test "--format json produces valid JSON that decodes and does not raise on tuples", ctx do
    output =
      capture_io(fn ->
        assert CompareTask.run(["--base", ctx.base_path, "--head", ctx.head_path, "--format", "json"]) ==
                 :ok
      end)

    decoded = Jason.decode!(output)

    assert decoded["schema"] == "excessibility.digest.compare/v1"
    # coverage.callbacks_added contained a {view, callback} tuple; jsonify/1
    # must have turned it into a 2-element list.
    assert [["PageLive", "handle_event:delete"]] = decoded["coverage"]["callbacks_added"]
  end

  test "missing --base prints usage error and exits non-zero", ctx do
    result =
      capture_io(:stderr, fn ->
        outcome =
          try do
            CompareTask.run(["--head", ctx.head_path])
            :no_exit
          catch
            :exit, reason -> {:exited, reason}
          end

        send(self(), {:outcome, outcome})
      end)

    assert_received {:outcome, {:exited, {:shutdown, 1}}}
    assert result =~ "--base"
  end
end
