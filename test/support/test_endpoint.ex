defmodule Excessibility.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :excessibility

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(:dispatch)

  defp dispatch(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, """
    <!DOCTYPE html>
    <html lang="en" dir="ltr">
      <head>
        <meta charset="UTF-8">
        <title>Test App</title>
        <link rel="stylesheet" href="/css/app.css">
      </head>
      <body>
        <div id="app"></div>
      </body>
    </html>
    """)
  end
end
