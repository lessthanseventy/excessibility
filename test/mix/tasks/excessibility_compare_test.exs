defmodule Mix.Tasks.Excessibility.CompareTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Excessibility.Compare, as: CompareTask

  @output_dir Path.join(["test", "excessibility"])
  @snapshot_dir Path.join(@output_dir, "html_snapshots")
  @baseline_dir Path.join(@output_dir, "baseline")

  setup do
    File.rm_rf!(@snapshot_dir)
    File.rm_rf!(@baseline_dir)
    File.mkdir_p!(@snapshot_dir)
    File.mkdir_p!(@baseline_dir)

    on_exit(fn ->
      File.rm_rf!(@snapshot_dir)
      File.rm_rf!(@baseline_dir)
    end)

    :ok
  end

  defp write_pair(name, baseline_html, current_html) do
    File.write!(Path.join(@baseline_dir, name), baseline_html)
    File.write!(Path.join(@snapshot_dir, name), current_html)
  end

  defp temp_diff_files do
    @snapshot_dir |> Path.join("*.{good,bad}.html") |> Path.wildcard()
  end

  test "reports when all snapshots match the baseline" do
    write_pair("home.html", "<div>same</div>", "<div>same</div>")

    output = capture_io(fn -> CompareTask.run([]) end)

    assert output =~ "match baseline"
  end

  # Under capture_io stdin is not a TTY, which is exactly the CI/agent
  # situation from issue #134: prompting would read :eof. The task must
  # refuse with guidance instead of crashing in parse_choice/1 — and
  # since it refuses before writing .good/.bad pairs, nothing leaks.
  test "refuses to prompt when stdin is not interactive" do
    write_pair("home.html", "<div>old</div>", "<div>new</div>")

    assert_raise Mix.Error, ~r/--keep/, fn ->
      capture_io(fn -> CompareTask.run([]) end)
    end

    assert temp_diff_files() == []
    assert File.read!(Path.join(@baseline_dir, "home.html")) == "<div>old</div>"
  end

  test "--keep good keeps all baselines and cleans up temp files" do
    write_pair("home.html", "<div>old</div>", "<div>new</div>")

    output = capture_io(fn -> CompareTask.run(["--keep", "good"]) end)

    assert output =~ "Kept baseline for home.html"
    assert File.read!(Path.join(@baseline_dir, "home.html")) == "<div>old</div>"
    assert temp_diff_files() == []
  end

  test "--keep bad accepts all new versions and cleans up temp files" do
    write_pair("home.html", "<div>old</div>", "<div>new</div>")

    output = capture_io(fn -> CompareTask.run(["--keep", "bad"]) end)

    assert output =~ "Updated baseline for home.html"
    assert File.read!(Path.join(@baseline_dir, "home.html")) == "<div>new</div>"
    assert temp_diff_files() == []
  end
end
