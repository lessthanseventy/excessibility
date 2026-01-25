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

    Excessibility.Snapshot.html_snapshot(conn, %{line: 0}, __MODULE__, open_browser?: true)

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

    Excessibility.Snapshot.html_snapshot(conn, %{line: 50}, __MODULE__, cleanup?: true)

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

  @tag :screenshot
  test "generates screenshots when screenshot? option is true" do
    filename = "screenshot_test.html"
    snapshot_path = Path.join(["test/excessibility/html_snapshots", filename])
    png_path = String.replace(snapshot_path, ".html", ".png")

    File.mkdir_p!("test/excessibility/html_snapshots")

    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<html><body>Screenshot test</body></html>")

    Excessibility.Snapshot.html_snapshot(conn, %{line: 0}, __MODULE__,
      screenshot?: true,
      name: filename
    )

    assert File.exists?(snapshot_path)
    assert File.exists?(png_path)

    File.rm_rf!("test/excessibility/html_snapshots")
  end
end
