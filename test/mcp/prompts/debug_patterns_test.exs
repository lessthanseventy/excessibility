defmodule Excessibility.MCP.Prompts.DebugPatternsTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Prompts.FixEventCascade
  alias Excessibility.MCP.Prompts.FixMemoryLeak
  alias Excessibility.MCP.Prompts.OptimizeLiveview

  describe "OptimizeLiveview" do
    test "returns correct name" do
      assert OptimizeLiveview.name() == "optimize-liveview"
    end

    test "has required symptom argument" do
      args = OptimizeLiveview.arguments()
      symptom_arg = Enum.find(args, &(&1["name"] == "symptom"))

      assert symptom_arg["required"] == true
    end

    test "generates optimization prompt for slow_render" do
      {:ok, result} = OptimizeLiveview.get(%{"symptom" => "slow_render"})
      text = get_prompt_text(result)

      assert text =~ "Slow Rendering"
      assert text =~ "Change Tracking"
      assert text =~ "assign"
      assert text =~ "stream"
    end

    test "generates optimization prompt for high_memory" do
      {:ok, result} = OptimizeLiveview.get(%{"symptom" => "high_memory"})
      text = get_prompt_text(result)

      assert text =~ "High Memory"
      assert text =~ "Unbounded lists"
      assert text =~ "stream"
    end

    test "generates optimization prompt for slow_events" do
      {:ok, result} = OptimizeLiveview.get(%{"symptom" => "slow_events"})
      text = get_prompt_text(result)

      assert text =~ "Slow Event Handling"
      assert text =~ "Blocking operations"
    end

    test "generates optimization prompt for laggy_ui" do
      {:ok, result} = OptimizeLiveview.get(%{"symptom" => "laggy_ui"})
      text = get_prompt_text(result)

      assert text =~ "Laggy"
      assert text =~ "phx-debounce"
    end

    test "generates optimization prompt for slow_mount" do
      {:ok, result} = OptimizeLiveview.get(%{"symptom" => "slow_mount"})
      text = get_prompt_text(result)

      assert text =~ "Slow Mount"
      assert text =~ "connected?"
    end

    test "includes general patterns" do
      {:ok, result} = OptimizeLiveview.get(%{"symptom" => "slow_render"})
      text = get_prompt_text(result)

      assert text =~ "Streams for Large Collections"
      assert text =~ "Preload Associations"
      assert text =~ "Async Operations"
    end

    test "includes context when provided" do
      {:ok, result} =
        OptimizeLiveview.get(%{"symptom" => "slow_render", "context" => "rendering 1000 items"})

      text = get_prompt_text(result)

      assert text =~ "rendering 1000 items"
    end
  end

  describe "FixMemoryLeak" do
    test "returns correct name" do
      assert FixMemoryLeak.name() == "fix-memory-leak"
    end

    test "has required pattern argument" do
      args = FixMemoryLeak.arguments()
      pattern_arg = Enum.find(args, &(&1["name"] == "pattern"))

      assert pattern_arg["required"] == true
    end

    test "generates fix for growing_list pattern" do
      {:ok, result} = FixMemoryLeak.get(%{"pattern" => "growing_list"})
      text = get_prompt_text(result)

      assert text =~ "Growing List"
      assert text =~ "stream"
      assert text =~ "Sliding Window"
      assert text =~ "Enum.take"
    end

    test "generates fix for retained_data pattern" do
      {:ok, result} = FixMemoryLeak.get(%{"pattern" => "retained_data"})
      text = get_prompt_text(result)

      assert text =~ "Retained Data"
      assert text =~ "Clear When Not Needed"
      assert text =~ "temporary_assigns"
    end

    test "generates fix for binary_accumulation pattern" do
      {:ok, result} = FixMemoryLeak.get(%{"pattern" => "binary_accumulation"})
      text = get_prompt_text(result)

      assert text =~ "Binary Accumulation"
      assert text =~ "Store References"
      assert text =~ "consume_uploaded_entries"
    end

    test "generates fix for subscription_leak pattern" do
      {:ok, result} = FixMemoryLeak.get(%{"pattern" => "subscription_leak"})
      text = get_prompt_text(result)

      assert text =~ "Subscription Leak"
      assert text =~ "unsubscribe"
      assert text =~ "terminate"
    end

    test "generates fix for ets_leak pattern" do
      {:ok, result} = FixMemoryLeak.get(%{"pattern" => "ets_leak"})
      text = get_prompt_text(result)

      assert text =~ "ETS Table"
      assert text =~ ":ets.delete"
      assert text =~ "Cachex"
    end

    test "includes detection instructions" do
      {:ok, result} = FixMemoryLeak.get(%{"pattern" => "growing_list"})
      text = get_prompt_text(result)

      assert text =~ "mix excessibility.debug"
      assert text =~ "--analyze=memory"
    end
  end

  describe "FixEventCascade" do
    test "returns correct name" do
      assert FixEventCascade.name() == "fix-event-cascade"
    end

    test "generates fix for chain_reaction cascade" do
      {:ok, result} = FixEventCascade.get(%{"cascade_type" => "chain_reaction"})
      text = get_prompt_text(result)

      assert text =~ "Chain Reaction"
      assert text =~ "Batch All Updates"
      assert text =~ "Single assign"
    end

    test "generates fix for infinite_loop cascade" do
      {:ok, result} = FixEventCascade.get(%{"cascade_type" => "infinite_loop"})
      text = get_prompt_text(result)

      assert text =~ "Infinite Loop"
      assert text =~ "Guard Conditions"
      assert text =~ "Source-of-Truth"
    end

    test "generates fix for rapid_fire cascade" do
      {:ok, result} = FixEventCascade.get(%{"cascade_type" => "rapid_fire"})
      text = get_prompt_text(result)

      assert text =~ "Rapid Fire"
      assert text =~ "phx-debounce"
      assert text =~ "phx-throttle"
    end

    test "generates fix for mutual_trigger cascade" do
      {:ok, result} = FixEventCascade.get(%{"cascade_type" => "mutual_trigger"})
      text = get_prompt_text(result)

      assert text =~ "Mutual Trigger"
      assert text =~ "Unidirectional Data Flow"
      assert text =~ "Single Source of Truth"
    end

    test "includes events when provided" do
      {:ok, result} =
        FixEventCascade.get(%{"events" => "update, validate, save"})

      text = get_prompt_text(result)

      assert text =~ "update, validate, save"
    end

    test "includes code context when provided" do
      code = """
      def handle_event("a", _, socket) do
        send(self(), :b)
      end
      """

      {:ok, result} = FixEventCascade.get(%{"code_context" => code})
      text = get_prompt_text(result)

      assert text =~ "handle_event(\"a\""
    end

    test "includes detection instructions" do
      {:ok, result} = FixEventCascade.get(%{"cascade_type" => "chain_reaction"})
      text = get_prompt_text(result)

      assert text =~ "mix excessibility.debug"
      assert text =~ "cascade_effect"
    end
  end

  # Helper to extract prompt text from result
  defp get_prompt_text(%{"messages" => [%{"content" => %{"text" => text}}]}), do: text
end
