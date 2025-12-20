defmodule Excessibility.FullIntegrationTest do
  use ExUnit.Case

  test "creates snapshot from Plug.Conn via direct function call" do
    conn =
      :get
      |> Plug.Test.conn("/")
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

defmodule Excessibility.MacroIntegrationTest do
  @moduledoc """
  Tests the macro usage pattern that real users would follow.
  """
  use ExUnit.Case
  use Excessibility

  @snapshot_dir Path.join([File.cwd!(), "test/excessibility/html_snapshots"])

  setup do
    on_exit(fn ->
      # Clean up any snapshots created by this module
      @snapshot_dir
      |> Path.join("Elixir_Excessibility_MacroIntegrationTest_*.html")
      |> Path.wildcard()
      |> Enum.each(&File.rm/1)
    end)

    :ok
  end

  test "html_snapshot/1 macro creates snapshot file" do
    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<h1>Hello World</h1>")

    # This uses the macro, which should capture __ENV__ and __MODULE__
    result = html_snapshot(conn)

    # Should return conn unchanged (pipeline friendly)
    assert result == conn

    # File should exist - filename based on this module and line number
    expected_pattern = Path.join(@snapshot_dir, "Elixir_Excessibility_MacroIntegrationTest_*.html")
    files = Path.wildcard(expected_pattern)

    assert length(files) > 0,
           "Expected snapshot file matching #{expected_pattern}, but found none. " <>
             "Dir contents: #{inspect(File.ls!(@snapshot_dir))}"
  end
end
