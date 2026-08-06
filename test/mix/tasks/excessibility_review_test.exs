defmodule Mix.Tasks.Excessibility.ReviewTest do
  use ExUnit.Case

  import ExUnit.CaptureIO
  import Mox

  alias Mix.Tasks.Excessibility.Review, as: ReviewTask

  @output_dir Path.join(["test", "excessibility"])
  @snapshot_dir Path.join(@output_dir, "html_snapshots")
  @baseline_dir Path.join(@output_dir, "baseline")

  @table_two ~s(<table><tbody><tr><td>Request A</td></tr><tr><td>Request B</td></tr></tbody></table>)
  @table_one ~s(<table><tbody><tr><td>Request A</td></tr></tbody></table>)

  setup do
    File.rm_rf!(@snapshot_dir)
    File.rm_rf!(@baseline_dir)
    File.mkdir_p!(@snapshot_dir)
    File.mkdir_p!(@baseline_dir)

    on_exit(fn ->
      File.rm_rf!(@snapshot_dir)
      File.rm_rf!(@baseline_dir)
    end)

    :ok
  end

  defp write_pair(name, baseline_html, current_html) do
    File.write!(Path.join(@baseline_dir, name), "<html><body>#{baseline_html}</body></html>")
    File.write!(Path.join(@snapshot_dir, name), "<html><body>#{current_html}</body></html>")
  end

  test "reports no changes when snapshots match the baseline" do
    write_pair("home.html", "<div>hi</div>", "<div>hi</div>")

    output = capture_io(fn -> ReviewTask.run([]) end)

    assert output =~ "No changes vs baseline"
  end

  test "blocks on a newly introduced serious violation" do
    write_pair("editor.html", "<div>Save</div>", ~s(<div phx-click="save">Save</div>))

    output =
      capture_io(fn ->
        assert catch_exit(ReviewTask.run([])) == {:shutdown, 1}
      end)

    assert output =~ "[BLOCK] editor.html"
    assert output =~ "phx_click_on_non_interactive"
    assert output =~ "1 block"
  end

  test "a content change without aria-live is :auto by default (independent-run fixtures)" do
    write_pair("orders.html", @table_two, @table_one)

    output = capture_io(fn -> ReviewTask.run([]) end)

    assert output =~ "[AUTO] orders.html"
    refute output =~ "content_change_without_live_region"
    assert output =~ "1 auto"
  end

  test "--content-diff flags a content change without aria-live as :review" do
    write_pair("orders.html", @table_two, @table_one)

    output = capture_io(fn -> ReviewTask.run(["--content-diff"]) end)

    assert output =~ "[REVIEW] orders.html"
    assert output =~ "content_change_without_live_region"
    assert output =~ "1 review"
  end

  test "--fail-on review exits non-zero on a review-tier change" do
    write_pair("orders.html", @table_two, @table_one)

    capture_io(fn ->
      assert catch_exit(ReviewTask.run(["--content-diff", "--fail-on", "review"])) == {:shutdown, 1}
    end)
  end

  test "--judge enriches the report with the judge's blast-radius summary" do
    write_pair("editor.html", "<div>Save</div>", ~s(<div phx-click="save">Save</div>))

    output =
      capture_io(fn ->
        assert catch_exit(ReviewTask.run(["--judge"])) == {:shutdown, 1}
      end)

    assert output =~ "[BLOCK] editor.html"
    # default heuristic judge's blast-radius summary
    assert output =~ "a11y finding(s)"
    assert output =~ "[serious] div"
  end

  test "a change inside a live region is :auto and does not block" do
    write_pair(
      "search.html",
      ~s(<div aria-live="polite"><p>0 results</p></div>),
      ~s(<div aria-live="polite"><p>1 result</p></div>)
    )

    output = capture_io(fn -> ReviewTask.run([]) end)

    assert output =~ "[AUTO] search.html"
    assert output =~ "1 auto"
  end

  test "warns when current snapshots predate the baseline" do
    write_pair("home.html", "<div>a</div>", "<div>a</div>")

    stale_mtime = {{2020, 1, 1}, {0, 0, 0}}
    File.touch!(Path.join(@snapshot_dir, "home.html"), stale_mtime)

    output = capture_io(fn -> ReviewTask.run([]) end)

    assert output =~ "predate the baseline"
    assert output =~ "mix test"
  end

  test "does not warn when snapshots are fresh" do
    write_pair("home.html", "<div>a</div>", "<div>a</div>")

    output = capture_io(fn -> ReviewTask.run([]) end)

    refute output =~ "predate the baseline"
  end

  test "--timeline with a missing file raises a friendly error" do
    write_pair("home.html", "<div>a</div>", "<div>a</div>")

    assert_raise Mix.Error, ~r/Could not read timeline/, fn ->
      capture_io(fn -> ReviewTask.run(["--timeline", "nope.json"]) end)
    end
  end

  test "--timeline with invalid JSON raises a friendly error" do
    write_pair("home.html", "<div>a</div>", "<div>a</div>")
    timeline_path = Path.join(@output_dir, "bad_timeline.json")
    File.write!(timeline_path, "{not json")
    on_exit(fn -> File.rm_rf!(timeline_path) end)

    assert_raise Mix.Error, ~r/Could not parse timeline JSON/, fn ->
      capture_io(fn -> ReviewTask.run(["--timeline", timeline_path]) end)
    end
  end

  test "--timeline loads a telemetry timeline and runs cleanly" do
    timeline_path = Path.join(@output_dir, "timeline.json")
    File.write!(timeline_path, ~s({"test":"x","timeline":[]}))
    on_exit(fn -> File.rm_rf!(timeline_path) end)

    write_pair("orders.html", @table_two, @table_one)

    output = capture_io(fn -> ReviewTask.run(["--timeline", timeline_path]) end)

    assert output =~ "orders.html"
  end

  describe "behavioral findings gating (issue #142)" do
    # A single-view timeline with a genuine serious memory finding (10x+ growth
    # past the absolute floor), so the exit behavior is exercised for real.
    @serious_timeline ~s({
      "test": "x",
      "duration_ms": 100,
      "timeline": [
        {"sequence": 0, "event": "mount", "view_module": "AppWeb.Index", "total_memory": 300000},
        {"sequence": 1, "event": "render", "view_module": "AppWeb.Index", "total_memory": 5000000},
        {"sequence": 2, "event": "render", "view_module": "AppWeb.Index", "total_memory": 5100000}
      ]
    })

    setup do
      timeline_path = Path.join(@output_dir, "serious_timeline.json")
      File.write!(timeline_path, @serious_timeline)
      on_exit(fn -> File.rm_rf!(timeline_path) end)
      {:ok, timeline_path: timeline_path}
    end

    test "a serious behavioral finding is advisory and does not exit by default", %{timeline_path: path} do
      write_pair("home.html", "<div>a</div>", "<div>a</div>")

      output = capture_io(fn -> ReviewTask.run(["--timeline", path]) end)

      assert output =~ "### Behavioral (telemetry analyzers)"
      assert output =~ "[serious] memory"
    end

    test "--fail-on-behavioral exits non-zero on a serious behavioral finding", %{timeline_path: path} do
      write_pair("home.html", "<div>a</div>", "<div>a</div>")

      capture_io(fn ->
        assert catch_exit(ReviewTask.run(["--timeline", path, "--fail-on-behavioral"])) == {:shutdown, 1}
      end)
    end

    test "--fail-on never still lets --fail-on-behavioral exit", %{timeline_path: path} do
      write_pair("home.html", "<div>a</div>", "<div>a</div>")

      capture_io(fn ->
        assert catch_exit(ReviewTask.run(["--timeline", path, "--fail-on", "never", "--fail-on-behavioral"])) ==
                 {:shutdown, 1}
      end)
    end
  end

  describe "JSON output (issue #143)" do
    test "--format json emits a single parseable object with the report shape" do
      write_pair("editor.html", "<div>Save</div>", ~s(<div phx-click="save">Save</div>))

      output =
        capture_io(fn ->
          assert catch_exit(ReviewTask.run(["--format", "json"])) == {:shutdown, 1}
        end)

      json = Jason.decode!(output)

      assert is_binary(json["excessibility_version"])
      assert json["summary"]["block"] == 1
      assert is_list(json["warnings"])
      assert is_list(json["behavioral"])

      change = Enum.find(json["changes"], &(&1["view"] == "editor.html"))
      assert change["tier"] == "block"

      finding = Enum.find(change["findings"], &(&1["rule"] == "phx_click_on_non_interactive"))
      assert finding["source"] == "live_view_rules"
      assert finding["severity"] in ["serious", "critical"]
      assert is_binary(finding["selector"])
    end

    test "--json is an alias for --format json" do
      write_pair("home.html", "<div>a</div>", "<div>a</div>")

      output = capture_io(fn -> ReviewTask.run(["--json"]) end)

      assert {:ok, decoded} = Jason.decode(output)
      assert Map.has_key?(decoded, "summary")
      # The human report text must not leak onto stdout in JSON mode.
      refute output =~ "Blast radius"
    end

    test "behavioral findings appear in JSON with a telemetry source", %{} do
      timeline_path = Path.join(@output_dir, "json_timeline.json")

      File.write!(
        timeline_path,
        ~s({"test":"x","duration_ms":100,"timeline":[
          {"sequence":0,"event":"mount","view_module":"AppWeb.Index","total_memory":300000},
          {"sequence":1,"event":"render","view_module":"AppWeb.Index","total_memory":5000000},
          {"sequence":2,"event":"render","view_module":"AppWeb.Index","total_memory":5100000}
        ]})
      )

      on_exit(fn -> File.rm_rf!(timeline_path) end)
      write_pair("home.html", "<div>a</div>", "<div>a</div>")

      output = capture_io(fn -> ReviewTask.run(["--json", "--timeline", timeline_path]) end)
      json = Jason.decode!(output)

      assert [finding | _] = json["behavioral"]
      assert finding["source"] == "telemetry"
      assert finding["rule"] == "memory"
      assert finding["severity"] == "serious"
    end

    test "the stale-snapshot notice moves into the JSON warnings array" do
      write_pair("home.html", "<div>a</div>", "<div>a</div>")
      File.touch!(Path.join(@snapshot_dir, "home.html"), {{2020, 1, 1}, {0, 0, 0}})

      output = capture_io(fn -> ReviewTask.run(["--json"]) end)
      json = Jason.decode!(output)

      assert Enum.any?(json["warnings"], &(&1 =~ "predate the baseline"))
      # No bare WARNING line on stdout to corrupt the JSON.
      refute output =~ "WARNING:"
    end
  end

  describe "axe-core findings" do
    setup :verify_on_exit!

    setup do
      Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerMock)
      on_exit(fn -> Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerStub) end)
      :ok
    end

    # The reproduction from issue #131: a visible button losing its text is
    # a new `button-name` critical, which must put the view in :block and
    # make the default --fail-on block exit non-zero.
    test "blocks on a newly introduced critical axe violation" do
      write_pair(
        "offer_detail.html",
        ~s(<button data-test-id="review-button">Review Order</button>),
        ~s(<button data-test-id="review-button"> </button>)
      )

      expect(Excessibility.ScannerMock, :scan, 2, fn "file://" <> path, _opts ->
        if File.read!(path) =~ "Review Order" do
          {:ok, %{violations: []}}
        else
          {:ok,
           %{
             violations: [
               %{
                 id: "button-name",
                 impact: :critical,
                 description: "Ensures buttons have discernible text",
                 help: "Buttons must have discernible text",
                 help_url: "https://dequeuniversity.com/rules/axe/4.11/button-name",
                 tags: ["wcag2a"],
                 nodes: [%{target: ["button"], html: "<button> </button>", failure_summary: "Fix it"}]
               }
             ]
           }}
        end
      end)

      output =
        capture_io(fn ->
          assert catch_exit(ReviewTask.run([])) == {:shutdown, 1}
        end)

      assert output =~ "[BLOCK] offer_detail.html"
      assert output =~ "button-name"
      assert output =~ "1 block"
    end

    test "--no-axe skips the scanner entirely" do
      write_pair("home.html", "<div>old</div>", "<div>new</div>")

      # No ScannerMock expectations: any scan call would raise.
      output = capture_io(fn -> ReviewTask.run(["--no-axe"]) end)

      assert output =~ "home.html"
    end

    test "a scan failure prints a warning and reviews on the LiveView rules alone" do
      write_pair("home.html", "<div>old</div>", "<div>new</div>")

      expect(Excessibility.ScannerMock, :scan, 2, fn _url, _opts ->
        {:error, {:playwright_error, "chromium not found"}}
      end)

      output = capture_io(fn -> ReviewTask.run([]) end)

      assert output =~ "WARNING: axe scan failed"
      assert output =~ "chromium not found"
      assert output =~ "home.html"
    end
  end
end
