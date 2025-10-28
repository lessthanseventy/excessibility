defmodule Excessibility.FullIntegrationTest do
  use ExUnit.Case

  test "creates snapshot from Plug.Conn" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<h1>Hello World</h1>")

    file_path =
      Path.join([
        File.cwd!(),
        "test/excessibility/html_snapshots",
        "Elixir_MyMod_42.html"
      ])

    Excessibility.Snapshot.html_snapshot(conn, %{line: 42}, MyMod, prompt_on_diff: false)
    Process.sleep(10)
    assert File.exists?(file_path)
    File.rm(file_path)
  end
end
