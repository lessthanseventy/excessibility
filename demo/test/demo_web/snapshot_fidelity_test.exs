defmodule DemoWeb.SnapshotFidelityTest do
  @moduledoc """
  A snapshot is what axe-core scans and what a screenshot shows, so it has to
  render like the page it was taken from. Each test loads the page from a real
  server and its snapshot from disk, both in Chromium with JavaScript off, and
  compares the render mode, the visible text and every element's box, at a
  desktop and a phone width.
  """
  use DemoWeb.ConnCase
  use Excessibility

  import Phoenix.LiveViewTest

  @moduletag :browser

  @probe Path.expand("../support/render_probe.js", __DIR__)
  @viewports "1280x800,375x800"

  setup_all do
    server =
      start_supervised!(
        {Bandit, plug: DemoWeb.Endpoint, ip: :loopback, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{base_url: "http://127.0.0.1:#{port}"}
  end

  for path <- ["/fidelity", "/accessible", "/a11y/form", "/a11y/widgets"] do
    @path path

    test "a LiveView snapshot of #{path} renders like the page", %{conn: conn, base_url: base_url} do
      {:ok, view, _html} = live(conn, @path, on_error: :warn)
      html_snapshot(view, name: snapshot_name(@path, "live"))

      assert_renders_like_page(base_url <> @path, snapshot_name(@path, "live"))
    end

    test "a controller snapshot of #{path} renders like the page", %{
      conn: conn,
      base_url: base_url
    } do
      conn |> get(@path) |> html_snapshot(name: snapshot_name(@path, "conn"))

      assert_renders_like_page(base_url <> @path, snapshot_name(@path, "conn"))
    end
  end

  defp snapshot_name(path, source), do: "fidelity_#{source}#{String.replace(path, "/", "_")}.html"

  defp assert_renders_like_page(page_url, snapshot_name) do
    snapshot_url =
      "file://" <> Path.expand(Path.join(Excessibility.Paths.snapshots_dir(), snapshot_name))

    for {viewport, [page, snapshot]} <- probe([page_url, snapshot_url]) do
      assert {viewport, page["failed"], snapshot["failed"]} == {viewport, [], []}
      assert {viewport, snapshot["compat_mode"]} == {viewport, page["compat_mode"]}
      assert {viewport, snapshot["text"]} == {viewport, page["text"]}
      assert {viewport, first_moved(page["elements"], snapshot["elements"])} == {viewport, nil}
    end
  end

  defp first_moved(page_elements, snapshot_elements)
       when length(page_elements) != length(snapshot_elements) do
    {:element_count, page: length(page_elements), snapshot: length(snapshot_elements)}
  end

  defp first_moved(page_elements, snapshot_elements) do
    page_elements
    |> Enum.zip(snapshot_elements)
    |> Enum.find(fn {page, snapshot} -> page != snapshot end)
  end

  defp probe(urls) do
    {output, status} =
      System.cmd("node", [@probe, @viewports | urls], env: [{"NODE_NO_WARNINGS", "1"}])

    assert status == 0, output
    Jason.decode!(output)
  end
end
