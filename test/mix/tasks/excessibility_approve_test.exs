defmodule Mix.Tasks.Excessibility.ApproveTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Mix.Tasks.Excessibility.Approve

  @snapshot_dir Path.join(["test", "excessibility", "html_snapshots"])
  @baseline_dir Path.join(["test", "excessibility", "baseline"])

  setup do
    File.rm_rf!(@snapshot_dir)
    File.rm_rf!(@baseline_dir)

    File.mkdir_p!(@snapshot_dir)
    File.mkdir_p!(@baseline_dir)

    :ok
  end

  defp seed_diff(name, good_html, bad_html) do
    File.write!(Path.join(@snapshot_dir, "#{name}.html"), good_html)
    File.write!(Path.join(@snapshot_dir, "#{name}.good.html"), good_html)
    File.write!(Path.join(@snapshot_dir, "#{name}.bad.html"), bad_html)
    File.write!(Path.join(@baseline_dir, "#{name}.html"), good_html)
  end

  test "--keep bad promotes the new HTML" do
    seed_diff("auto", "<p>old</p>", "<p>new</p>")

    Approve.run(["--keep", "bad"])

    assert File.read!(Path.join(@baseline_dir, "auto.html")) =~ "new"
    assert File.read!(Path.join(@snapshot_dir, "auto.html")) =~ "new"
    refute File.exists?(Path.join(@snapshot_dir, "auto.bad.html"))
    refute File.exists?(Path.join(@snapshot_dir, "auto.good.html"))
  end

  test "prompt keeps selected version" do
    seed_diff("prompted", "<p>old</p>", "<p>new</p>")

    capture_io("g\n", fn -> Approve.run([]) end)

    assert File.read!(Path.join(@baseline_dir, "prompted.html")) =~ "old"
    assert File.read!(Path.join(@snapshot_dir, "prompted.html")) =~ "old"
  end
end
