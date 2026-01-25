defmodule Excessibility.ErrorCasesTest do
  use ExUnit.Case

  describe "Snapshot screenshot failures" do
    test "handles ChromicPDF not started gracefully" do
      import ExUnit.CaptureLog
      # Stop ChromicPDF if it's running
      case Process.whereis(ChromicPDF) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html><body>Test</body></html>")

      # Should not crash, just log error
      _log =
        capture_log(fn ->
          Excessibility.Snapshot.html_snapshot(conn, %{line: 1}, __MODULE__,
            screenshot?: true,
            prompt_on_diff: false
          )
        end)

      # Verify the snapshot was still created even though screenshot failed
      snapshot_path =
        Path.join([
          File.cwd!(),
          "test/excessibility/html_snapshots",
          "Elixir_Excessibility_ErrorCasesTest_1.html"
        ])

      assert File.exists?(snapshot_path)
      File.rm(snapshot_path)

      # Restart ChromicPDF for other tests (handle already started case)
      case ChromicPDF.start_link(name: ChromicPDF) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end
  end

  describe "Source protocol with invalid data" do
    test "Plug.Conn with non-200 status raises" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(404, "<html><body>Not Found</body></html>")

      # Phoenix.ConnTest.html_response/2 raises RuntimeError for non-200 status
      assert_raise RuntimeError, ~r/expected response with status 200, got: 404/, fn ->
        Excessibility.Source.to_html(conn)
      end
    end
  end
end
