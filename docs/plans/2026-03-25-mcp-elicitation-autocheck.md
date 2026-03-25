# MCP Elicitation + Auto-Check Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add MCP elicitation support and an automated a11y/perf checking workflow that Claude runs without being asked.

**Architecture:** New `Elicitation` module handles the MCP elicitation protocol (send request via stdout, read response from stdin). Tools receive an `elicit` callback in opts. A new `check_work` composite tool combines test running, a11y checking, and optional perf analysis. The installer writes CLAUDE.md instructions instead of `.claude_docs/`.

**Tech Stack:** Elixir, MCP protocol (JSON-RPC 2.0), GenServer, Igniter

---

### Task 1: Create Elicitation Module

**Files:**
- Create: `lib/excessibility/mcp/elicitation.ex`
- Test: `test/mcp/elicitation_test.exs`

**Step 1: Write the failing test**

```elixir
# test/mcp/elicitation_test.exs
defmodule Excessibility.MCP.ElicitationTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Elicitation

  describe "build_request/3" do
    test "builds valid JSON-RPC elicitation request" do
      request = Elicitation.build_request(
        1,
        "Found 3 violations. Fix now?",
        %{
          "type" => "object",
          "properties" => %{
            "action" => %{
              "type" => "string",
              "enum" => ["fix_all", "skip"],
              "enumNames" => ["Fix all", "Skip"]
            }
          },
          "required" => ["action"]
        }
      )

      assert request["jsonrpc"] == "2.0"
      assert request["id"] == 1
      assert request["method"] == "elicitation/create"
      assert request["params"]["message"] == "Found 3 violations. Fix now?"
      assert request["params"]["requestedSchema"]["type"] == "object"
    end
  end

  describe "parse_response/1" do
    test "parses accepted response with content" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{
          "action" => "accept",
          "content" => %{"action" => "fix_all"}
        }
      }

      assert {:accept, %{"action" => "fix_all"}} = Elicitation.parse_response(response)
    end

    test "parses declined response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"action" => "decline"}
      }

      assert :decline = Elicitation.parse_response(response)
    end

    test "parses cancelled response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"action" => "cancel"}
      }

      assert :cancel = Elicitation.parse_response(response)
    end
  end

  describe "build_callback/2" do
    test "returns nil when io modules are nil" do
      assert Elicitation.build_callback(nil, nil) == nil
    end

    test "returns a function when io modules are provided" do
      callback = Elicitation.build_callback(&mock_write/1, &mock_read/0)
      assert is_function(callback, 2)
    end
  end

  # Mock IO functions for testing
  defp mock_write(_data), do: :ok
  defp mock_read, do: ~s({"jsonrpc":"2.0","id":1,"result":{"action":"accept","content":{"action":"fix_all"}}})
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/mcp/elicitation_test.exs`
Expected: FAIL — module `Excessibility.MCP.Elicitation` not found

**Step 3: Write minimal implementation**

```elixir
# lib/excessibility/mcp/elicitation.ex
defmodule Excessibility.MCP.Elicitation do
  @moduledoc """
  MCP elicitation support.

  Allows tools to request structured input from the user mid-execution
  via the MCP elicitation protocol (elicitation/create).

  Tools receive an `elicit` callback in their opts that they can call
  to pause execution and ask the user a question with a structured form.

  ## Usage in tools

      def execute(args, opts) do
        case Keyword.get(opts, :elicit) do
          nil ->
            # Elicitation not available, return full results
            {:ok, %{"violations" => all_violations}}

          elicit ->
            case elicit.("Found issues. Fix?", schema) do
              {:accept, %{"action" => "fix_all"}} -> ...
              :decline -> ...
              :cancel -> ...
            end
        end
      end
  """

  @doc """
  Builds a JSON-RPC elicitation/create request.
  """
  def build_request(id, message, requested_schema) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "elicitation/create",
      "params" => %{
        "message" => message,
        "requestedSchema" => requested_schema
      }
    }
  end

  @doc """
  Parses an elicitation response from the client.

  Returns:
  - `{:accept, content}` — user submitted the form
  - `:decline` — user explicitly rejected
  - `:cancel` — user dismissed
  """
  def parse_response(%{"result" => %{"action" => "accept", "content" => content}}),
    do: {:accept, content}

  def parse_response(%{"result" => %{"action" => "decline"}}),
    do: :decline

  def parse_response(%{"result" => %{"action" => "cancel"}}),
    do: :cancel

  @doc """
  Builds an elicit callback function for tools.

  Takes IO write/read functions for testability. In production these
  write to stdout and read from stdin. Returns nil if IO is unavailable
  (elicitation not supported by client).
  """
  def build_callback(nil, _read_fn), do: nil
  def build_callback(_write_fn, nil), do: nil

  def build_callback(write_fn, read_fn) do
    fn message, schema ->
      id = System.unique_integer([:positive])
      request = build_request(id, message, schema)
      json = Jason.encode!(request)

      write_fn.(json <> "\n")

      read_fn.()
      |> Jason.decode!()
      |> parse_response()
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/mcp/elicitation_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/excessibility/mcp/elicitation.ex test/mcp/elicitation_test.exs
git commit -m "feat: add MCP elicitation module"
```

---

### Task 2: Wire Elicitation Into Server

**Files:**
- Modify: `lib/excessibility/mcp/server.ex` (lines 33-37 capabilities, line 153 initialize, lines 289-312 call_tool)
- Modify: `lib/excessibility/mcp/tool.ex` (lines 44-46 opts docs)
- Test: `test/mcp/server_test.exs` (add elicitation capability tests)

**Step 1: Write the failing test**

Add to `test/mcp/server_test.exs`:

```elixir
describe "elicitation capability" do
  test "declares elicitation capability when supported", %{server: pid} do
    message = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{"elicitation" => %{}},
        "clientInfo" => %{"name" => "test"}
      }
    }

    response = Server.handle_rpc(pid, message)

    assert response["result"]["capabilities"]["elicitation"] == %{}
  end

  test "omits elicitation capability when client doesn't support it", %{server: pid} do
    message = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "test"}
      }
    }

    response = Server.handle_rpc(pid, message)

    refute Map.has_key?(response["result"]["capabilities"], "elicitation")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/mcp/server_test.exs --only elicitation` (tag the tests with `@tag :elicitation`)
Expected: FAIL — capabilities always static

**Step 3: Implement changes**

In `server.ex`:

1. Store client capabilities in GenServer state during initialize:

```elixir
# Update handle_message for initialize to check client capabilities
defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "initialize", "params" => params}, state) do
  client_caps = Map.get(params, "capabilities", %{})
  client_supports_elicitation? = Map.has_key?(client_caps, "elicitation")

  capabilities = build_capabilities(client_supports_elicitation?)

  # Store in state for later use in call_tool
  new_state = %{state | client_supports_elicitation: client_supports_elicitation?}

  {%{
    "jsonrpc" => "2.0",
    "id" => id,
    "result" => %{
      "protocolVersion" => "2024-11-05",
      "serverInfo" => @server_info,
      "capabilities" => capabilities
    }
  }, new_state}
end
```

2. Update `handle_call` to handle state updates from initialize:

```elixir
def handle_call({:handle_rpc, message}, _from, state) do
  case handle_message(message, state) do
    {response, new_state} -> {:reply, response, new_state}
    response -> {:reply, response, state}
  end
end
```

3. Add `client_supports_elicitation` to the struct:

```elixir
defstruct [:cache, client_supports_elicitation: false]
```

4. Build capabilities dynamically:

```elixir
defp build_capabilities(true = _elicitation?) do
  Map.put(@capabilities, "elicitation", %{})
end

defp build_capabilities(false), do: @capabilities
```

5. Update `call_tool` to pass elicit callback:

```elixir
defp call_tool(name, args, state) do
  case Registry.get_tool(name) do
    nil -> # ... error case unchanged
    tool_module ->
      opts = build_tool_opts(state)
      result = tool_module.execute(args, opts)
      Tool.format_result(result)
  end
end

defp build_tool_opts(%{client_supports_elicitation: true}) do
  elicit_fn = Elicitation.build_callback(
    &IO.binwrite(:stdio, &1),
    fn -> IO.read(:stdio, :line) |> String.trim() end
  )
  [elicit: elicit_fn]
end

defp build_tool_opts(_state), do: []
```

6. Update the `tools/call` handler to pass state:

```elixir
defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "tools/call", "params" => params}, state) do
  tool_name = Map.get(params, "name")
  arguments = Map.get(params, "arguments", %{})
  result = call_tool(tool_name, arguments, state)
  # ...
end
```

7. Update tool.ex opts docs to mention `:elicit`.

**Step 4: Run tests**

Run: `mix test test/mcp/server_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/excessibility/mcp/server.ex lib/excessibility/mcp/tool.ex test/mcp/server_test.exs
git commit -m "feat: wire elicitation support into MCP server"
```

---

### Task 3: Add Threshold-Based Elicitation to a11y_check

**Files:**
- Modify: `lib/excessibility/mcp/tools/a11y_check.ex`
- Test: `test/mcp/tools/a11y_check_test.exs`

**Step 1: Write the failing test**

```elixir
# Add to a11y_check_test.exs
describe "elicitation threshold" do
  test "does not elicit when no violations" do
    result = A11yCheck.maybe_elicit(%{"violations" => [], "violation_count" => 0}, nil)
    assert result == %{"violations" => [], "violation_count" => 0}
  end

  test "does not elicit when only minor violations" do
    violations = [%{"impact" => "minor", "id" => "heading-order"}]
    data = %{"violations" => violations, "violation_count" => 1}

    result = A11yCheck.maybe_elicit(data, nil)
    assert result == data
  end

  test "does not elicit when elicit callback is nil (client doesn't support)" do
    violations = [%{"impact" => "critical", "id" => "color-contrast"}]
    data = %{"violations" => violations, "violation_count" => 1}

    result = A11yCheck.maybe_elicit(data, nil)
    assert result == data
  end

  test "elicits when critical violations and callback available" do
    violations = [
      %{"impact" => "critical", "id" => "color-contrast", "nodes" => [%{}]},
      %{"impact" => "minor", "id" => "heading-order", "nodes" => [%{}]}
    ]
    data = %{"violations" => violations, "violation_count" => 2}

    elicit = fn _message, _schema ->
      {:accept, %{"action" => "fix_critical"}}
    end

    result = A11yCheck.maybe_elicit(data, elicit)

    # Should return only critical violations
    assert length(result["violations"]) == 1
    assert hd(result["violations"])["impact"] == "critical"
  end

  test "returns all violations when user chooses show_details" do
    violations = [
      %{"impact" => "critical", "id" => "color-contrast", "nodes" => [%{}]},
      %{"impact" => "minor", "id" => "heading-order", "nodes" => [%{}]}
    ]
    data = %{"violations" => violations, "violation_count" => 2}

    elicit = fn _message, _schema ->
      {:accept, %{"action" => "show_details"}}
    end

    result = A11yCheck.maybe_elicit(data, elicit)
    assert length(result["violations"]) == 2
  end

  test "returns skip marker when user declines" do
    violations = [%{"impact" => "critical", "id" => "color-contrast", "nodes" => [%{}]}]
    data = %{"violations" => violations, "violation_count" => 1}

    elicit = fn _message, _schema -> :decline end

    result = A11yCheck.maybe_elicit(data, elicit)
    assert result["skipped"] == true
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/mcp/tools/a11y_check_test.exs`
Expected: FAIL — `maybe_elicit/2` undefined

**Step 3: Implement**

Add to `a11y_check.ex`:

```elixir
@critical_impacts ~w(critical serious)

@elicitation_schema %{
  "type" => "object",
  "properties" => %{
    "action" => %{
      "type" => "string",
      "enum" => ["fix_all", "fix_critical", "show_details", "skip"],
      "enumNames" => ["Fix all violations now", "Fix critical only", "Show full details", "Skip"]
    }
  },
  "required" => ["action"]
}

def maybe_elicit(data, nil), do: data
def maybe_elicit(%{"violations" => []} = data, _elicit), do: data

def maybe_elicit(%{"violations" => violations} = data, elicit) do
  {critical, minor} = Enum.split_with(violations, &(&1["impact"] in @critical_impacts))

  if critical == [] do
    data
  else
    message = build_elicitation_message(critical, minor)

    case elicit.(message, @elicitation_schema) do
      {:accept, %{"action" => "fix_all"}} ->
        data

      {:accept, %{"action" => "fix_critical"}} ->
        %{data | "violations" => critical, "violation_count" => length(critical)}

      {:accept, %{"action" => "show_details"}} ->
        data

      {:accept, %{"action" => "skip"}} ->
        %{"skipped" => true, "violation_count" => length(violations)}

      :decline ->
        %{"skipped" => true, "violation_count" => length(violations)}

      :cancel ->
        %{"skipped" => true, "violation_count" => length(violations)}
    end
  end
end

defp build_elicitation_message(critical, minor) do
  critical_summary =
    critical
    |> Enum.map(& "- #{&1["id"]}: #{length(Map.get(&1, "nodes", []))} element(s)")
    |> Enum.join("\n")

  minor_count = length(minor)

  """
  Found #{length(critical)} critical/serious and #{minor_count} minor accessibility violations.

  Critical:
  #{critical_summary}
  """
end
```

Update `execute/2` to thread elicitation through:

```elixir
def execute(%{"url" => url}, opts) when is_binary(url) and url != "" do
  case check_url(url) do
    {:ok, data} ->
      elicit = Keyword.get(opts, :elicit)
      {:ok, maybe_elicit(data, elicit)}
    error -> error
  end
end

def execute(args, opts) do
  test_args = Map.get(args, "test_args", "")
  case run_mix_excessibility(test_args) do
    {:ok, data} ->
      elicit = Keyword.get(opts, :elicit)
      {:ok, maybe_elicit(data, elicit)}
    error -> error
  end
end
```

**Step 4: Run tests**

Run: `mix test test/mcp/tools/a11y_check_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/excessibility/mcp/tools/a11y_check.ex test/mcp/tools/a11y_check_test.exs
git commit -m "feat: add threshold-based elicitation to a11y_check"
```

---

### Task 4: Create check_work Composite Tool

**Files:**
- Create: `lib/excessibility/mcp/tools/check_work.ex`
- Test: `test/mcp/tools/check_work_test.exs`

**Step 1: Write the failing test**

```elixir
# test/mcp/tools/check_work_test.exs
defmodule Excessibility.MCP.Tools.CheckWorkTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.CheckWork

  describe "name/0" do
    test "returns tool name" do
      assert CheckWork.name() == "check_work"
    end
  end

  describe "input_schema/0" do
    test "requires test_file" do
      schema = CheckWork.input_schema()
      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "test_file")
      assert "test_file" in schema["required"]
    end

    test "has optional include_perf" do
      schema = CheckWork.input_schema()
      assert Map.has_key?(schema["properties"], "include_perf")
    end
  end

  describe "classify_violations/1" do
    test "returns :clean for no violations" do
      assert CheckWork.classify_violations([]) == :clean
    end

    test "returns :minor for only minor/moderate violations" do
      violations = [
        %{"impact" => "minor", "id" => "heading-order"},
        %{"impact" => "moderate", "id" => "link-name"}
      ]
      assert CheckWork.classify_violations(violations) == :minor
    end

    test "returns :critical for critical/serious violations" do
      violations = [
        %{"impact" => "critical", "id" => "color-contrast"},
        %{"impact" => "minor", "id" => "heading-order"}
      ]
      assert CheckWork.classify_violations(violations) == :critical
    end
  end

  describe "build_summary/2" do
    test "builds summary with a11y only" do
      a11y_result = %{"violation_count" => 3, "violations" => [
        %{"impact" => "critical", "id" => "color-contrast"},
        %{"impact" => "minor", "id" => "heading-order"},
        %{"impact" => "minor", "id" => "link-name"}
      ]}

      summary = CheckWork.build_summary(a11y_result, nil)
      assert summary =~ "1 critical"
      assert summary =~ "2 minor"
    end

    test "builds summary with perf findings" do
      a11y_result = %{"violation_count" => 1, "violations" => [
        %{"impact" => "critical", "id" => "color-contrast"}
      ]}
      perf_result = %{"findings" => [%{"type" => "n_plus_one", "message" => "N+1 in UserList"}]}

      summary = CheckWork.build_summary(a11y_result, perf_result)
      assert summary =~ "critical"
      assert summary =~ "N+1"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/mcp/tools/check_work_test.exs`
Expected: FAIL — module not found

**Step 3: Implement**

```elixir
# lib/excessibility/mcp/tools/check_work.ex
defmodule Excessibility.MCP.Tools.CheckWork do
  @moduledoc """
  Composite MCP tool that runs tests, accessibility checks, and optional
  performance analysis in one call.

  Designed to be called automatically by Claude after modifying code.
  Uses threshold-based elicitation to keep the user in control of triage.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext
  alias Excessibility.MCP.Subprocess

  @critical_impacts ~w(critical serious)

  @elicitation_schema %{
    "type" => "object",
    "properties" => %{
      "action" => %{
        "type" => "string",
        "enum" => ["fix_all", "fix_critical", "fix_a11y_only", "show_details", "skip"],
        "enumNames" => [
          "Fix all issues now",
          "Fix critical a11y + perf issues",
          "Fix a11y only",
          "Show full details",
          "Skip"
        ]
      }
    },
    "required" => ["action"]
  }

  @impl true
  def name, do: "check_work"

  @impl true
  def description do
    "Run tests, accessibility checks, and optional performance analysis. " <>
      "Designed to be called automatically after modifying code."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_file" => %{
          "type" => "string",
          "description" => "Test file to run (e.g., 'test/my_app_web/live/page_live_test.exs')"
        },
        "include_perf" => %{
          "type" => "boolean",
          "description" => "Also run timeline/performance analysis (default: false)"
        }
      },
      "required" => ["test_file"]
    }
  end

  @impl true
  def execute(args, opts) do
    test_file = Map.fetch!(args, "test_file")
    include_perf? = Map.get(args, "include_perf", false)
    cwd = ClientContext.get_cwd()
    elicit = Keyword.get(opts, :elicit)

    with {:ok, _test_output} <- run_tests(test_file, cwd),
         {:ok, a11y_result} <- run_a11y_check(cwd),
         {:ok, perf_result} <- maybe_run_perf(include_perf?, test_file, cwd) do
      build_result(a11y_result, perf_result, elicit)
    end
  end

  defp run_tests(test_file, cwd) do
    {output, exit_code} =
      Subprocess.run("mix", ["test", test_file],
        cd: cwd,
        stderr_to_stdout: true,
        timeout: 120_000
      )

    if exit_code == 0 do
      {:ok, output}
    else
      {:error, "Tests failed (exit #{exit_code}):\n#{output}"}
    end
  end

  defp run_a11y_check(cwd) do
    {output, exit_code} =
      Subprocess.run("mix", ["excessibility"],
        cd: cwd,
        stderr_to_stdout: true,
        timeout: 120_000
      )

    if exit_code == 0 do
      {:ok, %{"status" => "success", "output" => output, "violations" => [], "violation_count" => 0}}
    else
      # Parse violations from output if possible
      {:ok, %{"status" => "issues_found", "output" => output, "violations" => parse_violations(output), "violation_count" => count_violations(output)}}
    end
  end

  defp maybe_run_perf(false, _test_file, _cwd), do: {:ok, nil}

  defp maybe_run_perf(true, test_file, cwd) do
    {output, exit_code} =
      Subprocess.run("mix", ["excessibility.debug", test_file, "--format=json"],
        cd: cwd,
        stderr_to_stdout: true,
        timeout: 180_000,
        env: [{"EXCESSIBILITY_TELEMETRY_CAPTURE", "true"}]
      )

    if exit_code == 0 do
      case Jason.decode(output) do
        {:ok, data} -> {:ok, data}
        {:error, _} -> {:ok, %{"raw_output" => output}}
      end
    else
      {:ok, %{"status" => "error", "output" => output}}
    end
  end

  defp build_result(a11y_result, perf_result, elicit) do
    violations = Map.get(a11y_result, "violations", [])

    case {classify_violations(violations), has_perf_concerns?(perf_result), elicit} do
      {:clean, false, _} ->
        {:ok, %{"status" => "clean", "message" => "No issues found"}}

      {:minor, false, _} ->
        {:ok, %{"status" => "minor_issues", "a11y" => a11y_result, "perf" => perf_result}}

      {_, _, nil} ->
        # No elicitation available, return everything
        {:ok, %{"status" => "issues_found", "a11y" => a11y_result, "perf" => perf_result}}

      {_, _, elicit_fn} ->
        summary = build_summary(a11y_result, perf_result)

        case elicit_fn.(summary, @elicitation_schema) do
          {:accept, %{"action" => "fix_all"}} ->
            {:ok, %{"status" => "fix_all", "a11y" => a11y_result, "perf" => perf_result}}

          {:accept, %{"action" => "fix_critical"}} ->
            {:ok, %{"status" => "fix_critical", "a11y" => scope_critical(a11y_result), "perf" => perf_result}}

          {:accept, %{"action" => "fix_a11y_only"}} ->
            {:ok, %{"status" => "fix_a11y", "a11y" => a11y_result, "perf" => nil}}

          {:accept, %{"action" => "show_details"}} ->
            {:ok, %{"status" => "details", "a11y" => a11y_result, "perf" => perf_result}}

          {:accept, %{"action" => "skip"}} ->
            {:ok, %{"status" => "skipped"}}

          _ ->
            {:ok, %{"status" => "skipped"}}
        end
    end
  end

  def classify_violations([]), do: :clean

  def classify_violations(violations) do
    if Enum.any?(violations, &(&1["impact"] in @critical_impacts)),
      do: :critical,
      else: :minor
  end

  def build_summary(a11y_result, perf_result) do
    violations = Map.get(a11y_result, "violations", [])
    {critical, minor} = Enum.split_with(violations, &(&1["impact"] in @critical_impacts))

    a11y_line = "A11y: #{length(critical)} critical/serious, #{length(minor)} minor violations"

    perf_line =
      case perf_result do
        nil -> nil
        %{"findings" => findings} when is_list(findings) and findings != [] ->
          finding_lines = Enum.map(findings, & "- #{&1["message"]}") |> Enum.join("\n")
          "Perf:\n#{finding_lines}"
        _ -> nil
      end

    [a11y_line, perf_line]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp scope_critical(a11y_result) do
    violations = Map.get(a11y_result, "violations", [])
    critical = Enum.filter(violations, &(&1["impact"] in @critical_impacts))
    %{a11y_result | "violations" => critical, "violation_count" => length(critical)}
  end

  defp has_perf_concerns?(nil), do: false
  defp has_perf_concerns?(%{"findings" => f}) when is_list(f) and f != [], do: true
  defp has_perf_concerns?(_), do: false

  defp parse_violations(output) do
    # Best-effort parse — the actual violations come from axe-core structured output
    # This handles the case where we only have mix task text output
    if String.contains?(output, "violation") do
      [%{"impact" => "unknown", "id" => "parse_from_output", "description" => output}]
    else
      []
    end
  end

  defp count_violations(output) do
    case Regex.run(~r/(\d+) violation/, output) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end
end
```

**Step 4: Run tests**

Run: `mix test test/mcp/tools/check_work_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/excessibility/mcp/tools/check_work.ex test/mcp/tools/check_work_test.exs
git commit -m "feat: add check_work composite MCP tool"
```

---

### Task 5: Replace .claude_docs With CLAUDE.md in Installer

**Files:**
- Modify: `lib/mix/tasks/install.ex` (replace `maybe_create_claude_docs/1`, remove `claude_docs_content/0`)
- Delete: `lib/mix/tasks/excessibility_setup_claude_docs.ex`
- Test: `test/mix/tasks/install_test.exs` (if exists, update; otherwise manual verification)

**Step 1: Write the failing test**

Add to existing install tests or create:

```elixir
# Test the CLAUDE.md content generation
defmodule Mix.Tasks.Excessibility.InstallClaudeMdTest do
  use ExUnit.Case, async: true

  # Test the content helper directly
  test "claude_md_section/0 includes auto-check instructions" do
    content = Mix.Tasks.Excessibility.Install.claude_md_section()
    assert content =~ "## Excessibility"
    assert content =~ "check_work"
    assert content =~ "a11y_check"
    assert content =~ "/e11y-tdd"
  end

  test "claude_md_section/0 includes perf guidance" do
    content = Mix.Tasks.Excessibility.Install.claude_md_section()
    assert content =~ "include_perf"
    assert content =~ "performance"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/mix/tasks/install_claude_md_test.exs`
Expected: FAIL — `claude_md_section/0` undefined

**Step 3: Implement**

In `install.ex`, replace `maybe_create_claude_docs/1` with:

```elixir
defp maybe_setup_claude_md(igniter) do
  claude_md_path = "CLAUDE.md"
  section = claude_md_section()

  if File.exists?(claude_md_path) do
    Igniter.update_file(igniter, claude_md_path, fn source ->
      content = Rewrite.Source.get(source, :content)

      if String.contains?(content, "## Excessibility") do
        source
      else
        updated = content <> "\n\n" <> section
        Rewrite.Source.update(source, :content, updated)
      end
    end)
  else
    Igniter.create_or_update_file(igniter, claude_md_path, section, fn source -> source end)
  end
end

def claude_md_section do
  """
  ## Excessibility

  ### Automatic Accessibility Checking

  After modifying any LiveView, controller, or template code, run the `check_work` MCP tool
  with the relevant test file before reporting work as complete. Fix critical violations
  before moving on.

  ```
  check_work(test_file: "test/my_app_web/live/page_live_test.exs")
  ```

  When working on performance-sensitive code or investigating LiveView state issues,
  include performance analysis:

  ```
  check_work(test_file: "test/my_app_web/live/page_live_test.exs", include_perf: true)
  ```

  ### Available Skills

  - `/e11y-tdd` — TDD workflow with html_snapshot and axe-core accessibility checking
  - `/e11y-debug` — Debug workflow with timeline analysis for LiveView state inspection
  - `/e11y-fix` — Reference guide for fixing WCAG violations with Phoenix-specific patterns

  ### MCP Tools

  - `check_work` — Run tests + a11y check + optional perf analysis (use this automatically)
  - `a11y_check` — Run axe-core accessibility checks on snapshots or URLs
  - `debug` — Run tests with telemetry capture, returns timeline data
  - `get_snapshots` — List or read HTML snapshots from tests
  - `get_timeline` — Read captured timeline data
  - `generate_test` — Generate test code with html_snapshot() calls
  """
end
```

Update the pipeline in `igniter/0` to call `maybe_setup_claude_md` instead of `maybe_create_claude_docs`:

```elixir
igniter
|> ensure_test_config(endpoint, head_render_path)
|> ensure_test_helper()
|> maybe_install_deps(assets_dir, skip_npm?)
|> maybe_setup_claude_md()
|> maybe_setup_mcp(skip_mcp?)
```

Delete `claude_docs_content/0` private function from `install.ex`.

**Step 4: Run tests**

Run: `mix test test/mix/tasks/install_claude_md_test.exs`
Expected: PASS

**Step 5: Delete the old task file**

```bash
rm lib/mix/tasks/excessibility_setup_claude_docs.ex
```

**Step 6: Commit**

```bash
git add lib/mix/tasks/install.ex test/mix/tasks/install_claude_md_test.exs
git rm lib/mix/tasks/excessibility_setup_claude_docs.ex
git commit -m "feat: replace .claude_docs with CLAUDE.md in installer"
```

---

### Task 6: Update README

**Files:**
- Modify: `README.md`

**Step 1: Remove outdated sections**

Remove:
- "Claude Documentation" section (lines 175-181) referencing `.claude_docs` and `mix excessibility.setup_claude_docs`
- `mix excessibility.setup_claude_docs` from the Mix Tasks table (line 477)
- Outdated MCP manual setup JSON example (lines 224-234) referencing `mcp_servers.json`

**Step 2: Update "MCP Server & Claude Code Skills" section**

Replace lines 183-265 with updated content covering:
- What the installer sets up automatically (CLAUDE.md, MCP server, skills plugin)
- The auto-check workflow (Claude runs `check_work` after code changes)
- Elicitation-based triage for critical issues
- Updated tool table (add `check_work`)
- Optional hooks section with example `settings.json` config

**Step 3: Verify no broken references**

Search README for:
- `.claude_docs` — should be gone
- `setup_claude_docs` — should be gone
- `mcp_servers.json` — should be gone
- `check_route`, `explain_issue`, `suggest_fixes`, `analyze_timeline`, `list_analyzers` — should be gone

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README with auto-check workflow and elicitation"
```

---

### Task 7: Run Full Test Suite and Verify

**Step 1: Run all tests**

```bash
mix test
```

Expected: All pass

**Step 2: Run credo**

```bash
mix credo
```

Expected: No new issues

**Step 3: Run formatter**

```bash
mix format
```

**Step 4: Final commit if format changed anything**

```bash
git add -A
git commit -m "chore: format"
```
