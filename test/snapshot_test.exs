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
      on_exit(fn -> Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerStub) end)
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

  describe "screenshot viewports (#196)" do
    setup do
      Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerMock)

      on_exit(fn ->
        Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerStub)
        Application.delete_env(:excessibility, :viewports)
      end)
    end

    test "the :viewports option is forwarded to the screenshot scan" do
      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        assert Keyword.get(opts, :screenshot) =~ ".png"
        assert Keyword.get(opts, :viewports) == [{1440, 900}, {320, 800}]
        {:ok, %{}}
      end)

      snapshot(70, screenshot?: true, viewports: [{1440, 900}, {320, 800}])
    end

    test "the :viewports config is forwarded when no option is given" do
      Application.put_env(:excessibility, :viewports, [{390, 844}])

      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        assert Keyword.get(opts, :viewports) == [{390, 844}]
        {:ok, %{}}
      end)

      snapshot(71, screenshot?: true)
    end

    test "the :viewports option wins over the :viewports config" do
      Application.put_env(:excessibility, :viewports, [{390, 844}])

      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        assert Keyword.get(opts, :viewports) == [{320, 800}]
        {:ok, %{}}
      end)

      snapshot(72, screenshot?: true, viewports: [{320, 800}])
    end

    test "invalid viewports are dropped rather than passed through" do
      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        assert Keyword.get(opts, :viewports) == [{320, 800}]
        {:ok, %{}}
      end)

      snapshot(73, screenshot?: true, viewports: [{320, 800}, {0, 800}, "1440x900"])
    end

    test "no viewports configured leaves the scan at the single default" do
      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        assert Keyword.get(opts, :screenshot) =~ ".png"
        refute Keyword.has_key?(opts, :viewports)
        {:ok, %{}}
      end)

      snapshot(74, screenshot?: true)
    end

    test "every configured viewport's PNG path is logged" do
      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        # Stand in for the runner's per-viewport suffixing, so the log is
        # checked against files that genuinely exist.
        base = Keyword.fetch!(opts, :screenshot)

        for {w, h} <- Keyword.fetch!(opts, :viewports),
            do: File.write!(String.replace_suffix(base, ".png", ".#{w}x#{h}.png"), "png")

        {:ok, %{}}
      end)

      on_exit(fn ->
        Enum.each(
          Path.wildcard(Path.join([File.cwd!(), "test/excessibility/html_snapshots", "*_75.*png"])),
          &File.rm/1
        )
      end)

      log =
        capture_log(fn ->
          snapshot(75, screenshot?: true, viewports: [{1440, 900}, {320, 800}])
        end)

      assert log =~ "Elixir_Excessibility_SnapshotTest_75.1440x900.png"
      assert log =~ "Elixir_Excessibility_SnapshotTest_75.320x800.png"
    end

    test "a scan that reports success but writes no PNG is not logged as written" do
      # axe-runner.js swallows screenshot failures by design, so {:ok, _} does
      # not mean a file landed.
      expect(Excessibility.ScannerMock, :scan, fn _url, _opts -> {:ok, %{}} end)

      log = capture_log(fn -> snapshot(76, screenshot?: true, viewports: [{320, 800}]) end)

      assert log =~ "reported success but wrote no PNG"
      refute log =~ "Wrote screenshot"
    end

    test "only the widths whose PNG actually landed are claimed" do
      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        # Stand in for the runner: the 320x800 capture fails, 1440x900 does not.
        opts |> Keyword.fetch!(:screenshot) |> String.replace_suffix(".png", ".1440x900.png") |> File.write!("png")
        {:ok, %{}}
      end)

      log = capture_log(fn -> snapshot(77, screenshot?: true, viewports: [{1440, 900}, {320, 800}]) end)

      assert log =~ "Elixir_Excessibility_SnapshotTest_77.1440x900.png"
      refute log =~ "320x800"
    end

    test "PNGs from a previous width set are removed rather than left as stale evidence" do
      dir = Path.join([File.cwd!(), "test/excessibility/html_snapshots"])
      stale = Path.join(dir, "Elixir_Excessibility_SnapshotTest_78.320x800.png")
      bare = Path.join(dir, "Elixir_Excessibility_SnapshotTest_78.png")
      File.mkdir_p!(dir)
      File.write!(stale, "stale")
      File.write!(bare, "stale")
      on_exit(fn -> Enum.each(Path.wildcard(Path.join(dir, "*_78.*png")), &File.rm/1) end)

      expect(Excessibility.ScannerMock, :scan, fn _url, _opts -> {:ok, %{}} end)

      capture_log(fn -> snapshot(78, screenshot?: true, viewports: [{1440, 900}, {390, 844}]) end)

      refute File.exists?(stale)
      refute File.exists?(bare)
    end

    test "a custom :name without an .html suffix gets the viewport appended, as the runner does" do
      expect(Excessibility.ScannerMock, :scan, fn _url, opts ->
        assert Keyword.fetch!(opts, :screenshot) =~ "landing"
        opts |> Keyword.fetch!(:screenshot) |> Kernel.<>(".320x800.png") |> File.write!("png")
        {:ok, %{}}
      end)

      log = capture_log(fn -> snapshot(79, screenshot?: true, name: "landing", viewports: [{320, 800}]) end)

      assert log =~ "landing.320x800.png"

      on_exit(fn ->
        Enum.each(
          Path.wildcard(Path.join([File.cwd!(), "test/excessibility/html_snapshots", "landing*"])),
          &File.rm/1
        )
      end)
    end

    defp snapshot(line, opts) do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html><body>Hello</body></html>")

      Excessibility.Snapshot.html_snapshot(conn, %{line: line}, __MODULE__, opts)

      on_exit(fn ->
        File.rm(
          Path.join([
            File.cwd!(),
            "test/excessibility/html_snapshots",
            "Elixir_Excessibility_SnapshotTest_#{line}.html"
          ])
        )
      end)
    end
  end
end
