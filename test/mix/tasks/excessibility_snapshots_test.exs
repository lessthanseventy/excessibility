defmodule Mix.Tasks.Excessibility.SnapshotsTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Excessibility.Snapshots, as: SnapshotsTask

  @snapshot_dir "test/excessibility/html_snapshots"

  setup do
    File.mkdir_p!(@snapshot_dir)
    on_exit(fn -> File.rm_rf!(@snapshot_dir) end)
  end

  describe "list (no args)" do
    test "lists snapshots with sizes" do
      File.write!(Path.join(@snapshot_dir, "test1.html"), "<html></html>")
      File.write!(Path.join(@snapshot_dir, "test2.html"), "<html><body>more content</body></html>")

      output =
        capture_io(fn ->
          SnapshotsTask.run([])
        end)

      assert output =~ "test1.html"
      assert output =~ "test2.html"
      assert output =~ "2 snapshot(s)"
    end

    test "shows message when no snapshots" do
      File.rm_rf!(@snapshot_dir)

      output =
        capture_io(fn ->
          SnapshotsTask.run([])
        end)

      assert output =~ "No snapshots"
    end

    test "excludes .good.html and .bad.html files" do
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")
      File.write!(Path.join(@snapshot_dir, "test.good.html"), "<html></html>")
      File.write!(Path.join(@snapshot_dir, "test.bad.html"), "<html></html>")

      output =
        capture_io(fn ->
          SnapshotsTask.run([])
        end)

      assert output =~ "1 snapshot(s)"
      assert output =~ "test.html"
      refute output =~ "good.html"
      refute output =~ "bad.html"
    end
  end

  describe "--clean" do
    test "deletes all snapshots with confirmation" do
      File.write!(Path.join(@snapshot_dir, "test1.html"), "<html></html>")

      capture_io([input: "Y\n"], fn ->
        SnapshotsTask.run(["--clean"])
      end)

      assert @snapshot_dir |> Path.join("*.html") |> Path.wildcard() == []
    end

    test "reports when no snapshots to clean" do
      File.rm_rf!(@snapshot_dir)

      output =
        capture_io(fn ->
          SnapshotsTask.run(["--clean"])
        end)

      assert output =~ "No snapshots to clean"
    end
  end

  describe "--open" do
    test "reports error for nonexistent snapshot" do
      output =
        capture_io(:stderr, fn ->
          SnapshotsTask.run(["--open", "nonexistent.html"])
        end)

      assert output =~ "Snapshot not found"
    end
  end
end
