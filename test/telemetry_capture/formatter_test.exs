defmodule Excessibility.TelemetryCapture.FormatterTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Formatter

  describe "format_json/1" do
    test "encodes timeline as JSON" do
      timeline = %{
        test: "my_test",
        duration_ms: 500,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{user_id: 123},
            changes: nil
          }
        ]
      }

      result = Formatter.format_json(timeline)

      assert is_binary(result)
      decoded = Jason.decode!(result)
      assert decoded["test"] == "my_test"
      assert decoded["duration_ms"] == 500
      assert length(decoded["timeline"]) == 1
    end

    test "converts tuples to lists for JSON compatibility" do
      timeline = %{
        test: "test",
        duration_ms: 100,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{status: :pending},
            changes: %{"status" => {:pending, :complete}}
          }
        ]
      }

      result = Formatter.format_json(timeline)

      decoded = Jason.decode!(result)
      first_event = List.first(decoded["timeline"])
      # Tuple {old, new} becomes list [old, new] in JSON
      assert first_event["changes"]["status"] == ["pending", "complete"]
    end

    test "converts functions to string representation (defense-in-depth for #52)" do
      # Defense-in-depth: Even if filter misses a function, formatter shouldn't crash
      # Functions are converted to readable string representations like "#Function<name/arity>"
      func_ref = &String.length/1

      timeline = %{
        test: "test_with_function",
        duration_ms: 100,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{callback: func_ref, user_id: 123},
            changes: nil
          }
        ]
      }

      result = Formatter.format_json(timeline)

      # Should successfully encode without crashing
      assert is_binary(result)
      decoded = Jason.decode!(result)

      # Function should be converted to string
      first_event = List.first(decoded["timeline"])
      callback_value = first_event["key_state"]["callback"]

      # Should be a string representation, not crash
      assert is_binary(callback_value)
      assert callback_value =~ "#Function<"
      # arity
      assert callback_value =~ "/1>"
    end

    test "converts Ecto structs to maps for JSON encoding" do
      # Simulate an Ecto schema User struct
      user = %{
        __struct__: User,
        __meta__: %{state: :loaded, source: "users"},
        id: 42,
        email: "test@example.com",
        name: "Test User"
      }

      timeline = %{
        test: "test_with_ecto",
        duration_ms: 200,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{current_user: user},
            changes: nil
          }
        ]
      }

      result = Formatter.format_json(timeline)

      # Should successfully encode without crashing
      assert is_binary(result)
      decoded = Jason.decode!(result)

      # Struct should be converted to map
      first_event = List.first(decoded["timeline"])
      user_data = first_event["key_state"]["current_user"]

      # Should have user fields but not __meta__
      assert user_data["id"] == 42
      assert user_data["email"] == "test@example.com"
      assert user_data["name"] == "Test User"
      refute Map.has_key?(user_data, "__meta__")
    end
  end

  describe "format_markdown/2" do
    test "generates markdown with timeline table" do
      timeline = %{
        test: "purchase_flow",
        duration_ms: 850,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00.000Z],
            key_state: %{user_id: 123, cart_items_count: 0},
            changes: nil,
            duration_since_previous_ms: nil
          },
          %{
            sequence: 2,
            event: "handle_event:add_to_cart",
            timestamp: ~U[2026-01-25 10:00:00.350Z],
            key_state: %{user_id: 123, cart_items_count: 1},
            changes: %{"cart_items_count" => {0, 1}},
            duration_since_previous_ms: 350
          }
        ]
      }

      result = Formatter.format_markdown(timeline, [])

      assert result =~ "# Test Debug Report: purchase_flow"
      assert result =~ "850ms"
      assert result =~ "| # | Time | Event | Key Changes |"
      assert result =~ "| 1 | +0ms | mount |"
      assert result =~ "| 2 | +350ms | handle_event:add_to_cart | cart_items_count: 0→1 |"
    end

    test "generates detailed change sections" do
      timeline = %{
        test: "test",
        duration_ms: 100,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{status: :pending},
            changes: nil,
            duration_since_previous_ms: nil
          },
          %{
            sequence: 2,
            event: "submit",
            timestamp: ~U[2026-01-25 10:00:00.100Z],
            key_state: %{status: :complete},
            changes: %{"status" => {:pending, :complete}},
            duration_since_previous_ms: 100
          }
        ]
      }

      result = Formatter.format_markdown(timeline, [])

      assert result =~ "## Detailed Changes"
      assert result =~ "### Event 2: submit (+100ms)"
      assert result =~ "**State Changes:**"
      assert result =~ "- `status`: :pending → :complete"
    end

    test "handles list format from JSON deserialization (regression test for #54)" do
      # Reproduces the bug: timeline.json has lists, not tuples
      # This simulates what happens when we read timeline.json from disk
      timeline = %{
        test: "test_from_json",
        duration_ms: 200,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{user_id: 123},
            changes: nil,
            duration_since_previous_ms: nil
          },
          %{
            sequence: 2,
            event: "handle_event:click",
            timestamp: ~U[2026-01-25 10:00:00.200Z],
            key_state: %{user_id: 123, clicked: true},
            # Lists instead of tuples (as they come from JSON)
            changes: %{"clicked" => [false, true], "status" => ["pending", "done"]},
            duration_since_previous_ms: 200
          }
        ]
      }

      # Should not crash with FunctionClauseError
      result = Formatter.format_markdown(timeline, [])

      # Verify markdown is generated correctly
      assert result =~ "# Test Debug Report: test_from_json"
      assert result =~ "| 2 | +200ms | handle_event:click | clicked: false→true, status: \"pending\"→\"done\" |"
      assert result =~ "### Event 2: handle_event:click (+200ms)"
      assert result =~ "- `clicked`: false → true"
      assert result =~ "- `status`: \"pending\" → \"done\""
    end
  end

  describe "format_analysis_results/2" do
    test "formats empty results" do
      result = Formatter.format_analysis_results(%{}, [])
      assert result == ""
    end

    test "formats healthy analyzer result" do
      results = %{
        memory: %{
          findings: [],
          stats: %{min: 1000, max: 5000, avg: 3000}
        }
      }

      output = Formatter.format_analysis_results(results, [])

      assert output =~ "## Memory Analysis ✅"
      assert output =~ "1000 B"
      assert output =~ "4.9 KB"
    end

    test "formats analyzer with findings" do
      results = %{
        memory: %{
          findings: [
            %{
              severity: :warning,
              message: "Memory grew 5x",
              events: [1, 2],
              metadata: %{}
            }
          ],
          stats: %{min: 1000, max: 10_000}
        }
      }

      output = Formatter.format_analysis_results(results, [])

      assert output =~ "## Memory Analysis"
      refute output =~ "✅"
      assert output =~ "⚠️"
      assert output =~ "Memory grew 5x"
    end

    test "formats critical findings" do
      results = %{
        memory: %{
          findings: [
            %{
              severity: :critical,
              message: "Memory leak detected",
              events: [1, 2, 3],
              metadata: %{}
            }
          ],
          stats: %{}
        }
      }

      output = Formatter.format_analysis_results(results, [])

      assert output =~ "🔴"
      assert output =~ "Memory leak detected"
    end

    test "verbose mode shows detailed stats" do
      results = %{
        memory: %{
          findings: [],
          stats: %{min: 1000, max: 5000, avg: 3000, median: 2500}
        }
      }

      brief = Formatter.format_analysis_results(results, verbose: false)
      verbose = Formatter.format_analysis_results(results, verbose: true)

      assert String.length(verbose) > String.length(brief)
      assert verbose =~ "Median"
    end

    test "includes suggested prompts when findings have them" do
      results = %{
        memory: %{
          findings: [
            %{
              severity: :warning,
              message: "Memory grew 5x",
              events: [1, 2],
              metadata: %{
                suggested_prompt: "What assigns are growing between events 1 and 2?"
              }
            }
          ],
          stats: %{}
        }
      }

      output = Formatter.format_analysis_results(results, [])

      assert output =~ "💡 Ask:"
      assert output =~ "What assigns are growing between events 1 and 2?"
    end

    test "handles findings without suggested prompts" do
      results = %{
        memory: %{
          findings: [
            %{
              severity: :info,
              message: "Normal operation",
              events: [],
              metadata: %{}
            }
          ],
          stats: %{}
        }
      }

      output = Formatter.format_analysis_results(results, [])

      assert output =~ "Normal operation"
      refute output =~ "💡"
    end
  end
end
