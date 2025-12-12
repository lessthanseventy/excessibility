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
