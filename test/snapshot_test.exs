defmodule Excessibility.SnapshotTest do
  use ExUnit.Case

  import Mox

  setup :verify_on_exit!

  setup do
    Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)
    :ok
  end

  test "respects open_browser? option by calling system" do
    filename = "Elixir_Excessibility_SnapshotTest_0.html"
    full_path = Path.join([File.cwd!(), "test/excessibility/html_snapshots", filename])

    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<html><body>Hello</body></html>")

    expect(Excessibility.SystemMock, :open_with_system_cmd, fn actual_path ->
      assert actual_path == full_path
      :ok
    end)

    Excessibility.Snapshot.html_snapshot(conn, %{line: 0}, __MODULE__,
      open_browser?: true,
      prompt_on_diff: false
    )

    assert File.exists?(full_path)
    File.rm(full_path)
  end

  test "cleanup? option deletes existing snapshots for module" do
    snapshot_dir = Path.join([File.cwd!(), "test/excessibility/html_snapshots"])
    File.mkdir_p!(snapshot_dir)

    # Create some existing snapshots for this module
    File.write!(Path.join(snapshot_dir, "Elixir_Excessibility_SnapshotTest_10.html"), "old1")
    File.write!(Path.join(snapshot_dir, "Elixir_Excessibility_SnapshotTest_20.html"), "old2")

    # Create a snapshot for a different module (should not be deleted)
    File.write!(Path.join(snapshot_dir, "Elixir_OtherModule_30.html"), "other")

    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<html><body>New</body></html>")

    Excessibility.Snapshot.html_snapshot(conn, %{line: 50}, __MODULE__,
      cleanup?: true,
      prompt_on_diff: false
    )

    # Old snapshots for this module should be deleted
    refute File.exists?(Path.join(snapshot_dir, "Elixir_Excessibility_SnapshotTest_10.html"))
    refute File.exists?(Path.join(snapshot_dir, "Elixir_Excessibility_SnapshotTest_20.html"))

    # Snapshot for other module should still exist
    assert File.exists?(Path.join(snapshot_dir, "Elixir_OtherModule_30.html"))

    # New snapshot should exist
    assert File.exists?(Path.join(snapshot_dir, "Elixir_Excessibility_SnapshotTest_50.html"))

    # Cleanup
    File.rm_rf!(snapshot_dir)
  end
end

defmodule Excessibility.ScreenshotTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  test "generates screenshots for diffed snapshots" do
    filename = "diff_test.html"
    baseline_path = Path.join(["test/excessibility/baseline", filename])
    snapshot_path = Path.join(["test/excessibility/html_snapshots", filename])
    good_png = String.replace(snapshot_path, ".html", ".good.png")
    bad_png = String.replace(snapshot_path, ".html", ".bad.png")

    File.mkdir_p!("test/excessibility/baseline")
    File.mkdir_p!("test/excessibility/html_snapshots")

    File.write!(baseline_path, "<html><body>Baseline</body></html>")

    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<html><body>Changed</body></html>")

    Excessibility.Snapshot.html_snapshot(conn, %{line: 0}, __MODULE__,
      tag_on_diff: true,
      prompt_on_diff: false,
      screenshot?: true,
      name: "diff_test.html"
    )

    assert File.exists?(good_png)
    assert File.exists?(bad_png)

    File.rm_rf!("test/excessibility/html_snapshots")
    File.rm_rf!("test/excessibility/baseline")
  end
end
