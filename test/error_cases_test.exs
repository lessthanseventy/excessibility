defmodule Excessibility.ErrorCasesTest do
  use ExUnit.Case

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
