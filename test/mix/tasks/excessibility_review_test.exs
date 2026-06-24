defmodule Mix.Tasks.Excessibility.ReviewTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

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

  test "a content change without aria-live is :review (does not block by default)" do
    write_pair("orders.html", @table_two, @table_one)

    output = capture_io(fn -> ReviewTask.run([]) end)

    assert output =~ "[REVIEW] orders.html"
    assert output =~ "content_change_without_live_region"
    assert output =~ "1 review"
  end

  test "--fail-on review exits non-zero on a review-tier change" do
    write_pair("orders.html", @table_two, @table_one)

    capture_io(fn ->
      assert catch_exit(ReviewTask.run(["--fail-on", "review"])) == {:shutdown, 1}
    end)
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
end
