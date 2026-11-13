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

  describe "diff/3 — normalize_numbers: true" do
    test "text that differs only by record ids, UUIDs and sequences is unchanged" do
      old =
        ~s(<ul><li>Order 2741595</li><li>email-568@example.com</li><li>0ad113de-7c1e-4f0a-9b1d-3f2a6c5e8d90</li></ul>)

      new = ~s(<ul><li>Order 88</li><li>email-400@example.com</li><li>f3b9c2a1-1d2e-4a3b-8c4d-5e6f7a8b9c0d</li></ul>)

      assert [_ | _] = SnapshotDiff.diff(old, new)
      assert [] = SnapshotDiff.diff(old, new, normalize_numbers: true)
    end

    test "text that differs only by shortened UUIDs is unchanged" do
      old =
        ~s(<ul><li>Offer ID: c3b4c5</li><li>Chrome Baseball Offer - ID #e1b2b3b4b5</li><li>Ref 12345678</li><li>offer_9a1c2d3f</li></ul>)

      new =
        ~s(<ul><li>Offer ID: f9c1bcca</li><li>Chrome Baseball Offer - ID #9a1c2d3</li><li>Ref 9a1c2d3f</li><li>offer_f9c1bcca</li></ul>)

      assert [] = SnapshotDiff.diff(old, new, normalize_numbers: true)
    end

    test "a shortened UUID that is all letters is unchanged too" do
      old = ~s(<ul><li>Offer ID: fadecb</li><li>Ref DEADBEEF</li></ul>)
      new = ~s(<ul><li>Offer ID: c3b4c5</li><li>Ref 12345678</li></ul>)

      assert [] = SnapshotDiff.diff(old, new, normalize_numbers: true)
    end

    test "hex-letter words shorter than six characters are not collapsed" do
      old = ~s(<div><p>Row added</p><p>Total 3</p></div>)
      new = ~s(<div><p>Row faded</p><p>Total 4</p></div>)

      assert [_] = SnapshotDiff.diff(old, new, normalize_numbers: true)
    end

    test "a change in the words is still reported, with the raw text" do
      old = ~s(<div><p>Order 12 shipped</p><p>Total 3</p></div>)
      new = ~s(<div><p>Order 97 cancelled</p><p>Total 4</p></div>)

      assert [region] = SnapshotDiff.diff(old, new, normalize_numbers: true)
      assert region.old_text == "Order 12 shipped"
      assert region.new_text == "Order 97 cancelled"
    end
  end

  describe "render_equivalent?/2" do
    test "per-render tokens, comments and record ids are not differences" do
      old = """
      <!-- Timestamp: 1 -->
      <html><head><meta name="csrf-token" content="tokA"></head><body>
      <div id="phx-F1a_x-Q" data-phx-main data-phx-session="sessA" data-phx-static="statA">
      <input type="hidden" name="_csrf_token" value="tokA"><a data-csrf="tokA" href="/orders/12">Order 12</a>
      <p id="row-0ad113de-7c1e-4f0a-9b1d-3f2a6c5e8d90" data-phx-id="c3-phx-F1a_x-Q">c3b4c5</p>
      <label for="phx-F1a_upload" phx-drop-target="phx-F1a_upload" phx-click='[["dispatch",{"to":"#phx-F1a_upload"}]]'>Add</label>
      </div></body></html>
      """

      new = """
      <!-- Timestamp: 2 -->
      <html><head><meta name="csrf-token" content="tokB"></head><body>
      <div id="phx-G2b-y_R" data-phx-main data-phx-session="sessB" data-phx-static="statB">
      <input type="hidden" name="_csrf_token" value="tokB"><a data-csrf="tokB" href="/orders/407">Order 407</a>
      <p id="row-f3b9c2a1-1d2e-4a3b-8c4d-5e6f7a8b9c0d" data-phx-id="c3-phx-G2b-y_R">9a1c2d</p>
      <label for="phx-G2b-upload" phx-drop-target="phx-G2b-upload" phx-click='[["dispatch",{"to":"#phx-G2b-upload"}]]'>Add</label>
      </div></body></html>
      """

      assert SnapshotDiff.render_equivalent?(old, new)
    end

    test "a signed Phoenix token in a URL is not a difference" do
      old = ~s(<a href="/share?token=SFMyNTY.g2gDYgArYQxuBgCjy9fToQFiAAFRgA.Ro2LZrKCAO2hg7po4X5eoLM-glUGI6gw">Share</a>)
      new = ~s(<a href="/share?token=SFMyNTY.g2gDYgBqV1huBgB_xNrToQFiAAFRgA.c9Jq0V_3mXw1x7pT2bKfLhQ8sYd5nRzA">Share</a>)

      assert SnapshotDiff.render_equivalent?(old, new)
    end

    # Each pair differs only in an id, so collapsing ids to one placeholder
    # would call them equal; what changed is which element the id reaches.
    for {label, old, new} <- [
          {"a label that stops pointing at its input", ~s(<label for="f1">L</label><input id="f1">),
           ~s(<label for="f2">L</label><input id="f1">)},
          {"an aria-labelledby that stops resolving", ~s(<span id="l1">Name</span><input aria-labelledby="l1">),
           ~s(<span id="l1">Name</span><input aria-labelledby="l2">)},
          {"a skip link that loses its target", ~s(<a href="#main1">Skip</a><main id="main1">y</main>),
           ~s(<a href="#main2">Skip</a><main id="main1">y</main>)},
          {"two ids becoming one", ~s(<input id="x1" aria-label="a"><input id="x2" aria-label="a">),
           ~s(<input id="x1" aria-label="a"><input id="x1" aria-label="a">)},
          {"two radio groups becoming one", ~s(<input type="radio" name="g1"><input type="radio" name="g2">),
           ~s(<input type="radio" name="g1"><input type="radio" name="g1">)},
          {"a hex-looking id that stops matching", ~s(<label for="facade">L</label><input id="facade">),
           ~s(<label for="decade">L</label><input id="facade">)},
          {"an id moving to another rule of a style block",
           ~s(<style>#box1{color:#eee}#box2{color:#000}</style><p id="box1">hi</p>),
           ~s(<style>#box1{color:#eee}#box2{color:#000}</style><p id="box2">hi</p>)},
          {"a data attribute moving to another rule of a style block",
           ~s(<style>[data-level="1"]{color:#eee}[data-level="2"]{color:#000}</style><p data-level="1">hi</p>),
           ~s(<style>[data-level="1"]{color:#eee}[data-level="2"]{color:#000}</style><p data-level="2">hi</p>)},
          {"a label that stops pointing at its input, with its attributes reordered",
           ~s(<label class="l" for="f-2">L</label><input id="f-2">),
           ~s(<label for="f-2" class="l">L</label><input id="f-3">)},
          {"an srcset pointing at another file", ~s(<img src="/p.png" srcset="/p.png 500w">),
           ~s(<img src="/p.png" srcset="/q.png 500w">)},
          {"a doctype being dropped", "<!DOCTYPE html><html><body><p>a</p></body></html>",
           "<html><body><p>a</p></body></html>"}
        ] do
      test "#{label} is a difference" do
        refute SnapshotDiff.render_equivalent?(unquote(old), unquote(new))
      end
    end

    test "an id that differs the same way everywhere it is used is not a difference" do
      old = ~s(<label for="qty-12">Quantity</label><input id="qty-12" name="items[12]"><a href="/orders/12">Open</a>)
      new = ~s(<label for="qty-97">Quantity</label><input id="qty-97" name="items[97]"><a href="/orders/97">Open</a>)

      assert SnapshotDiff.render_equivalent?(old, new)
    end

    test "attribute order is not a difference" do
      old = ~s(<label class="l" for="qty-12">Q</label><a href="/x/12" class="btn" data-test-id="go">Go</a>)
      new = ~s(<label for="qty-97" class="l">Q</label><a href="/x/97" data-test-id="go" class="btn">Go</a>)

      assert SnapshotDiff.render_equivalent?(old, new)
    end

    test "a record id in srcset that differs as it does in src is not a difference" do
      old = ~s(<img src="/p.png#252-500px" srcset="/p.png#252-500px 500w, /p.png#252-original 1000w">)
      new = ~s(<img src="/p.png#239-500px" srcset="/p.png#239-500px 500w, /p.png#239-original 1000w">)

      assert SnapshotDiff.render_equivalent?(old, new)
    end

    test "a record id equal to a number in a JS command's classes or time is not a difference" do
      toggle = ~s([["toggle",{"to":"#menu","ins":[["duration-300"],["opacity-0"],["opacity-100"]],"time":300}]])
      old = ~s(<p id="row-297">a</p><button phx-click='#{toggle}'>Menu</button>)
      new = ~s(<p id="row-300">a</p><button phx-click='#{toggle}'>Menu</button>)

      assert SnapshotDiff.render_equivalent?(old, new)
    end

    test "a record id under a pushed value's key named like a JS class argument is not a difference" do
      old = ~s(<b phx-click='[["push",{"event":"pick","value":{"time":12,"names":"u12"}}]]'>x</b>)
      new = ~s(<b phx-click='[["push",{"event":"pick","value":{"time":97,"names":"u97"}}]]'>x</b>)

      assert SnapshotDiff.render_equivalent?(old, new)
    end

    test "a processing instruction is compared, not crashed on" do
      refute SnapshotDiff.render_equivalent?(~s(<?xml version="1.0"?><p>a</p>), "<p>a</p>")
    end

    test "byte-identical documents are equivalent even when they do not parse to a tree" do
      assert SnapshotDiff.render_equivalent?("", "")
    end

    for {label, old, new} <- [
          {"a class", ~s(<p class="text-neutral-900">x</p>), ~s(<p class="text-neutral-400">x</p>)},
          {"an inline style", ~s(<p style="color: #111111">x</p>), ~s(<p style="color: #cccccc">x</p>)},
          {"a style block", "<style>p { color: #111111 }</style><p>x</p>",
           "<style>p { color: #cccccc }</style><p>x</p>"},
          {"a stylesheet link", ~s(<link rel="stylesheet" href="/app-0a1b2c3d.css">),
           ~s(<link rel="stylesheet" href="/app-4e5f6a7b.css">)},
          {"a class in a JS command", ~s(<p phx-click='[["add_class",{"names":["duration-300"]}]]'>x</p>),
           ~s(<p phx-click='[["add_class",{"names":["duration-700"]}]]'>x</p>)},
          {"a JS command's target", ~s(<p id="m1">x</p><p id="m2">y</p><b phx-click='[["show",{"to":"#m1"}]]'>s</b>),
           ~s(<p id="m1">x</p><p id="m2">y</p><b phx-click='[["show",{"to":"#m2"}]]'>s</b>)},
          {"an srcset width descriptor", ~s(<img srcset="/a.png 400w">), ~s(<img srcset="/a.png 800w">)},
          {"an srcset density descriptor", ~s(<img srcset="/a.png 1x, /b.png 1.5x">),
           ~s(<img srcset="/a.png 1x, /b.png 2x">)},
          {"a number becoming a string in a JS command",
           ~s(<p phx-click='[["push",{"event":"x","value":{"n":1}}]]'>x</p>),
           ~s(<p phx-click='[["push",{"event":"x","value":{"n":"1"}}]]'>x</p>)},
          {"a tabindex", ~s(<p tabindex="0">x</p>), ~s(<p tabindex="3">x</p>)},
          {"an attribute being added", "<p>x</p>", ~s(<p hidden>x</p>)},
          {"a word in the text", "<p>Save</p>", "<p>Submit</p>"},
          {"a non-token meta", ~s(<meta name="viewport" content="width=1">),
           ~s(<meta name="viewport" content="width=2">)},
          {"an attribute name", ~s(<input name="a" value="1">), ~s(<input name="a" placeholder="1">)}
        ] do
      test "#{label} that differs is a difference" do
        refute SnapshotDiff.render_equivalent?(unquote(old), unquote(new))
      end
    end
  end

  describe "live_region_findings/3 — content change without aria-live" do
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

  describe "scan_sequence/2 — same-view identity guard" do
    # Wrap a body in a LiveView main root carrying a per-mount id, the way a
    # captured LiveView snapshot looks. A fresh `live/2` mount gets a new id;
    # an in-place patch keeps the same id.
    defp lv(id, body) do
      ~s(<html><body><div data-phx-main data-phx-session="tok" id="#{id}">#{body}</div></body></html>)
    end

    test "skips a pair whose LiveView root id changed (full navigation)" do
      dashboard = lv("phx-AAA", "<main><h1>Dashboard</h1></main>")
      events = lv("phx-BBB", "<main><h1>Events</h1><table><tbody><tr><td>x</td></tr></tbody></table></main>")

      assert [] = SnapshotDiff.scan_sequence([dashboard, events])
    end

    test "still flags an in-place patch that keeps the same root id" do
      before = lv("phx-AAA", @table_two)
      later = lv("phx-AAA", @table_one)

      assert [finding] = SnapshotDiff.scan_sequence([before, later])
      assert finding.rule == :content_change_without_live_region
    end

    test "treats LiveView->non-LiveView (root presence differs) as a navigation" do
      # A LiveView cannot patch into a dead controller render, so a rooted
      # snapshot followed by an unrooted one is a page change, not a patch.
      live = lv("phx-AAA", @table_two)
      plain = ~s(<html><body>#{@table_one}</body></html>)

      assert [] = SnapshotDiff.scan_sequence([live, plain])
    end

    test "still diffs a neither-rooted pair (truly indeterminate, no regression)" do
      # No LiveView root on either side and a bounded, overlapping change:
      # nothing proves navigation, so it is diffed and flagged.
      before = ~s(<html><body>#{@table_two}</body></html>)
      later = ~s(<html><body>#{@table_one}</body></html>)

      assert [_] = SnapshotDiff.scan_sequence([before, later])
    end

    test "keys on the main root when a nested LiveView is present" do
      # Same page patched: main id stable, nested child remounts. Same view.
      nested_a = ~s(<div data-phx-session="c" data-phx-parent-id="phx-AAA" id="phx-C1">#{@table_two}</div>)
      nested_b = ~s(<div data-phx-session="c" data-phx-parent-id="phx-AAA" id="phx-C2">#{@table_one}</div>)
      before = lv("phx-AAA", nested_a)
      later = lv("phx-AAA", nested_b)

      assert [_] = SnapshotDiff.scan_sequence([before, later])
    end
  end

  describe "navigation-scale changes — dead-render navigations" do
    # A page whose whole <body> subtree differs in structure from the next,
    # the way a LiveView -> controller (dead render) transition looks: no
    # shared LiveView root, divergent top-level markup, disjoint text.
    @event_page ~s(<html><body><div class="lv"><h1>Event Detail</h1><p>Concert tickets venue doors midnight support artist lineup schedule map parking</p></div></body></html>)
    @login_page ~s(<html><body><main class="auth"><h1>Log in</h1><form><label>Email password remember forgot register submit credentials account</label></form></main></body></html>)
    @register_page ~s(<html><body><section class="signup"><h1>Create account</h1><form><label>Name birthday phone confirm terms newsletter subscribe finish welcome</label></form></section></body></html>)

    test "skips a LiveView->controller navigation (whole body replaced, no shared root)" do
      assert [] = SnapshotDiff.scan_sequence([@event_page, @login_page])
    end

    test "skips a controller->controller navigation" do
      assert [] = SnapshotDiff.scan_sequence([@login_page, @register_page])
    end

    test "skips a LiveView->controller navigation via root presence, not text" do
      # The clean signal: a LiveView (has root) cannot patch into a dead
      # controller render (no root), so presence-differs is a navigation.
      live = lv("phx-AAA", "<h1>Event Detail</h1><p>tickets venue doors artist</p>")
      controller = @login_page

      assert [] = SnapshotDiff.scan_sequence([live, controller])
    end

    test "never treats a same-view in-place patch as navigation, even when tiny and fully replaced" do
      # A toast/counter that is the bulk
      # of a small LiveView and whose text fully changes must stay flagged —
      # identity (same root id) protects it, not text ratios.
      toast_before = lv("phx-AAA", ~s(<div class="toast">Saved</div>))
      toast_after = lv("phx-AAA", ~s(<div class="toast">Error occurred</div>))
      assert [_] = SnapshotDiff.scan_sequence([toast_before, toast_after])

      count_before = lv("phx-AAA", ~s(<span id="count">0</span>))
      count_after = lv("phx-AAA", ~s(<span id="count">5</span>))
      assert [_] = SnapshotDiff.scan_sequence([count_before, count_after])
    end

    test "flags a tiny fully-replaced status even in a non-rooted fragment (size floor)" do
      # No LiveView root, no chrome padding: the size floor keeps a short
      # status region from being mistaken for a whole-page navigation.
      before = ~s(<html><body><div id="status">Loading</div></body></html>)
      later = ~s(<html><body><div id="status">Done</div></body></html>)

      assert [_] = SnapshotDiff.scan_sequence([before, later])
    end

    test "still flags a small status update inside an otherwise-stable page" do
      # Bulk of the page (nav + list) is unchanged; only a tiny status region
      # flips. Low coverage keeps it a real un-announced status message.
      chrome = String.duplicate("<li>home about events tags admin members settings help</li>", 6)
      before = ~s(<html><body><nav><ul>#{chrome}</ul></nav><main><div id="status">Loading</div></main></body></html>)

      later =
        ~s(<html><body><nav><ul>#{chrome}</ul></nav><main><div id="status">42 results found</div></main></body></html>)

      assert [finding] = SnapshotDiff.scan_sequence([before, later])
      assert finding.selector =~ "status"
    end

    test "still flags a large but mostly-stable feed losing one item" do
      # Feed dominates the page (high coverage) but most items are unchanged
      # (high overlap), so it is an in-place update, not a navigation.
      rows = fn extra -> Enum.map_join(1..12, "", &"<li>Item #{&1} approved active visible</li>") <> extra end
      before = ~s(<html><body><main><ul>#{rows.("<li>Item 13 approved active visible</li>")}</ul></main></body></html>)
      later = ~s(<html><body><main><ul>#{rows.("")}</ul></main></body></html>)

      assert [_] = SnapshotDiff.scan_sequence([before, later])
    end
  end

  describe "user-input controls — typed content is not a status message" do
    test "does not flag a changed <textarea> value" do
      before = ~s(<html><body><form><textarea id="event_description">Draft one</textarea></form></body></html>)
      later = ~s(<html><body><form><textarea id="event_description">Draft two edited</textarea></form></body></html>)

      assert [] = SnapshotDiff.scan_sequence([before, later])
    end

    test "does not flag a change inside a [contenteditable] region" do
      before = ~s(<html><body><div contenteditable="true"><p>hello there</p></div></body></html>)
      later = ~s(<html><body><div contenteditable="true"><p>hello there world edited</p></div></body></html>)

      assert [] = SnapshotDiff.scan_sequence([before, later])
    end

    test "still flags a normal non-input region that changed" do
      before = ~s(<html><body><section><p id="count">0 results</p></section></body></html>)
      later = ~s(<html><body><section><p id="count">5 results</p></section></body></html>)

      assert [_] = SnapshotDiff.scan_sequence([before, later])
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

    test "skips paired files whose LiveView root id changed", %{dir: dir} do
      body_a = ~s(<div data-phx-main id="phx-AAA"><main><h1>Dashboard</h1></main></div>)
      body_b = ~s(<div data-phx-main id="phx-BBB"><main><h1>Events</h1>#{@table_one}</main></div>)
      p1 = write_snap(dir, "j_1.html", "journey test", 1, body_a)
      p2 = write_snap(dir, "j_2.html", "journey test", 2, body_b)

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
