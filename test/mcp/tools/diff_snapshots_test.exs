defmodule Excessibility.MCP.Tools.DiffSnapshotsTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.DiffSnapshots

  @before "<html><body><table><tbody><tr><td>A</td></tr><tr><td>B</td></tr></tbody></table></body></html>"
  @current "<html><body><table><tbody><tr><td>A</td></tr></tbody></table></body></html>"

  test "flags a content change without aria-live and tiers it review" do
    {:ok, result} = DiffSnapshots.execute(%{"before" => @before, "after" => @current}, [])

    assert result["status"] == "success"
    assert result["tier"] == "review"
    assert result["regions_changed"] == 1
    assert Enum.any?(result["findings"], &(&1["rule"] == "content_change_without_live_region"))
  end

  test "reports a newly introduced keyboard-inaccessible control as block" do
    before = "<html><body><div>Save</div></body></html>"
    current = ~s(<html><body><div phx-click="save">Save</div></body></html>)

    {:ok, result} = DiffSnapshots.execute(%{"before" => before, "after" => current}, [])

    assert result["tier"] == "block"
    assert Enum.any?(result["findings"], &(&1["rule"] == "phx_click_on_non_interactive"))
  end

  test "a clean diff is tier auto with no findings" do
    html = "<html><body><p>same</p></body></html>"

    {:ok, result} = DiffSnapshots.execute(%{"before" => html, "after" => html}, [])

    assert result["tier"] == "auto"
    assert result["findings"] == []
    assert result["regions_changed"] == 0
  end

  test "missing arguments returns an error" do
    assert {:error, message} = DiffSnapshots.execute(%{"before" => "<p>x</p>"}, [])
    assert message =~ "before and after"
  end

  test "is discoverable by the MCP registry" do
    assert Excessibility.MCP.Registry.get_tool("diff_snapshots") == DiffSnapshots
  end
end
