defmodule Excessibility.SnapshotTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
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

  describe "screenshot failures" do
    setup do
      Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerMock)
      on_exit(fn -> Application.delete_env(:excessibility, :scanner_mod) end)
    end

    test "a failed screenshot logs the reason and keeps the HTML snapshot" do
      filename = "Elixir_Excessibility_SnapshotTest_60.html"
      full_path = Path.join([File.cwd!(), "test/excessibility/html_snapshots", filename])

      expect(Excessibility.ScannerMock, :scan, fn url, opts ->
        assert url =~ ".html"
        assert Keyword.get(opts, :screenshot) =~ ".png"
        {:error, {:playwright_error, ""}}
      end)

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html><body>Hello</body></html>")

      log =
        capture_log(fn ->
          Excessibility.Snapshot.html_snapshot(conn, %{line: 60}, __MODULE__, screenshot?: true)
        end)

      assert log =~ "Screenshot failed"
      assert log =~ "playwright_error"
      assert File.exists?(full_path)

      File.rm(full_path)
    end
  end
end
