defmodule Excessibility.SnapshotDiffTest do
  use ExUnit.Case, async: true

  alias Excessibility.SnapshotDiff

  defp regions(old, new), do: SnapshotDiff.diff(old, new)
  defp findings(old, new), do: SnapshotDiff.live_region_findings(old, new)

  defp write_snap(dir, name, test, sequence, body) do
    path = Path.join(dir, name)

    content =
      "<!--\nExcessibility Snapshot\nTest: #{test}\nSequence: #{sequence}\n-->\n" <>
        "<html><body>#{body}</body></html>"

    File.write!(path, content)
    path
  end

  # A LiveView patch that filters a table from two rows to one.
  @table_two ~s(<table><tbody><tr><td>Request A</td></tr><tr><td>Request B</td></tr></tbody></table>)
  @table_one ~s(<table><tbody><tr><td>Request A</td></tr></tbody></table>)

  describe "diff/3 — generic DOM diff" do
    test "returns no regions when content is identical" do
      assert [] = regions(@table_two, @table_two)
    end

    test "detects a changed container and localizes to it" do
      assert [region] = regions(@table_two, @table_one)
      assert region.change == :changed
      assert region.selector =~ "tbody"
      assert region.old_text =~ "Request B"
      refute region.new_text =~ "Request B"
    end

    test "localizes a change to the deepest stable element" do
      old = ~s(<section><div id="a"><span>1</span></div><div id="b"><span>x</span></div></section>)
      new = ~s(<section><div id="a"><span>2</span></div><div id="b"><span>x</span></div></section>)

      assert [region] = regions(old, new)
      assert region.new_text =~ "2"
      refute region.new_text =~ "x"
    end

    test "detects changes in an element's own text nodes" do
      old = ~s(<p id="count">0 results <strong>here</strong></p>)
      new = ~s(<p id="count">5 results <strong>here</strong></p>)

      assert [region] = regions(old, new)
      assert region.selector =~ "count"
    end

    test "ignores whitespace-only differences" do
      old = ~s(<div><p>Hello</p></div>)
      new = ~s(<div>\n   <p>Hello</p>\n</div>)

      assert [] = regions(old, new)
    end
  end

  describe "live_region_findings/3 — content change without aria-live (issue #104)" do
    test "flags a significant content change outside any live region" do
      assert [finding] = findings(@table_two, @table_one)
      assert finding.rule == :content_change_without_live_region
      assert finding.message =~ "aria-live"
      assert finding.selector =~ "tbody"
    end

    test "does not flag a change inside an aria-live container" do
      old = ~s(<div aria-live="polite">#{@table_two}</div>)
      new = ~s(<div aria-live="polite">#{@table_one}</div>)

      assert [] = findings(old, new)
      # but the generic diff still sees the change
      assert [_] = regions(old, new)
    end

    test "does not flag a change inside role=status / alert / log" do
      for role <- ~w(status alert log) do
        old = ~s(<div role="#{role}">#{@table_two}</div>)
        new = ~s(<div role="#{role}">#{@table_one}</div>)
        assert [] = findings(old, new), "expected role=#{role} to be treated as a live region"
      end
    end

    test "does not flag a change inside an <output> element" do
      old = ~s(<output>#{@table_two}</output>)
      new = ~s(<output>#{@table_one}</output>)
      assert [] = findings(old, new)
    end

    test "aria-live=\"off\" is not a live region and is still flagged" do
      old = ~s(<div aria-live="off">#{@table_two}</div>)
      new = ~s(<div aria-live="off">#{@table_one}</div>)
      assert [_] = findings(old, new)
    end

    test "treats an ancestor live region as announced" do
      old = ~s(<section role="status"><table><tbody><tr><td>a</td></tr></tbody></table></section>)
      new = ~s(<section role="status"><table><tbody><tr><td>a</td></tr><tr><td>b</td></tr></tbody></table></section>)

      assert [] = findings(old, new)
    end
  end

  describe "scan_sequence/2 — consecutive snapshot pairs" do
    test "diffs each consecutive pair and aggregates findings" do
      s1 = @table_two
      s2 = @table_one
      s3 = ~s(<table><tbody><tr><td>Request A</td></tr><tr><td>Request C</td></tr></tbody></table>)

      findings = SnapshotDiff.scan_sequence([s1, s2, s3])
      assert length(findings) == 2
      assert Enum.all?(findings, &(&1.rule == :content_change_without_live_region))
    end

    test "returns no findings for a single snapshot" do
      assert [] = SnapshotDiff.scan_sequence([@table_two])
    end
  end

  describe "scan_files/2 — pair snapshots by captured test metadata" do
    setup do
      dir = Path.join(System.tmp_dir!(), "excessibility_diff_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "diffs consecutive snapshots within the same test, ordered by sequence", %{dir: dir} do
      p1 = write_snap(dir, "t_1_initial.html", "page test", 1, @table_two)
      p2 = write_snap(dir, "t_2_filter.html", "page test", 2, @table_one)

      # Pass out of order — grouping sorts by sequence.
      assert [{file, finding}] = SnapshotDiff.scan_files([p2, p1])
      assert file == p2
      assert finding.rule == :content_change_without_live_region
    end

    test "does not cross-chain snapshots from different tests", %{dir: dir} do
      p1 = write_snap(dir, "a_1.html", "test a", 1, @table_two)
      p2 = write_snap(dir, "b_1.html", "test b", 1, @table_one)

      assert [] = SnapshotDiff.scan_files([p1, p2])
    end

    test "skips snapshots without capture metadata", %{dir: dir} do
      p1 = Path.join(dir, "Mod_10.html")
      p2 = Path.join(dir, "Mod_20.html")
      File.write!(p1, "<html><body>#{@table_two}</body></html>")
      File.write!(p2, "<html><body>#{@table_one}</body></html>")

      assert [] = SnapshotDiff.scan_files([p1, p2])
    end

    test "respects live regions across paired files", %{dir: dir} do
      body_two = ~s(<div role="status">#{@table_two}</div>)
      body_one = ~s(<div role="status">#{@table_one}</div>)
      p1 = write_snap(dir, "t_1.html", "announced test", 1, body_two)
      p2 = write_snap(dir, "t_2.html", "announced test", 2, body_one)

      assert [] = SnapshotDiff.scan_files([p1, p2])
    end
  end
end
