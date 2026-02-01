defmodule Excessibility.MCP.Server do
  @moduledoc """
  Minimal MCP server for excessibility tools.

  Implements just enough of the MCP protocol for stdio transport:
  - JSON-RPC 2.0 message handling
  - initialize/initialized handshake
  - tools/list and tools/call

  ## Usage

      Excessibility.MCP.Server.start()

  Or via mix:

      mix run --no-halt -e "Excessibility.MCP.Server.start()"
  """

  @server_info %{
    "name" => "excessibility",
    "version" => "0.9.0"
  }

  @capabilities %{
    "tools" => %{}
  }

  @tools [
    %{
      "name" => "e11y_check",
      "description" =>
        "Run Pa11y accessibility checks on HTML snapshots. Without args: check existing snapshots. With test_args: run tests first, then check.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "test_args" => %{
            "type" => "string",
            "description" => "Arguments to pass to mix test (optional)"
          }
        }
      }
    },
    %{
      "name" => "e11y_debug",
      "description" => "Run tests with telemetry capture and timeline analysis for debugging LiveView state.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "test_args" => %{
            "type" => "string",
            "description" => "Arguments to pass to mix test (required)"
          },
          "analyzers" => %{
            "type" => "string",
            "description" => "Comma-separated list of analyzers to run"
          }
        },
        "required" => ["test_args"]
      }
    },
    %{
      "name" => "get_timeline",
      "description" => "Read the captured timeline showing LiveView state evolution at each event.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Custom path to timeline.json (optional)"
          }
        }
      }
    },
    %{
      "name" => "get_snapshots",
      "description" => "List or read HTML snapshots captured during tests.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "filter" => %{
            "type" => "string",
            "description" => "Glob pattern to filter snapshots (e.g., '*_test_*.html')"
          },
          "include_content" => %{
            "type" => "boolean",
            "description" => "Include HTML content in response"
          }
        }
      }
    }
  ]

  @doc """
  Starts the MCP server, reading from stdin and writing to stdout.
  """
  def start do
    # Disable logger output to stdout (would corrupt MCP messages)
    Logger.configure(level: :none)

    loop()
  end

  defp loop do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line ->
        line
        |> String.trim()
        |> handle_line()

        loop()
    end
  end

  defp handle_line(""), do: :ok

  defp handle_line(line) do
    case Jason.decode(line) do
      {:ok, message} ->
        response = handle_message(message)

        if response do
          send_response(response)
        end

      {:error, _} ->
        send_error(-32_700, "Parse error", nil)
    end
  end

  # Initialize request
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "initialize", "params" => params}) do
    _client_info = Map.get(params, "clientInfo", %{})
    _protocol_version = Map.get(params, "protocolVersion")

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "serverInfo" => @server_info,
        "capabilities" => @capabilities
      }
    }
  end

  # Initialized notification (no response needed)
  defp handle_message(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}) do
    nil
  end

  # Tools list
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "tools/list"}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "tools" => @tools
      }
    }
  end

  # Tools call
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "tools/call", "params" => params}) do
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    result = call_tool(tool_name, arguments)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  # Ping
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "ping"}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{}
    }
  end

  # Unknown method
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => method}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => -32_601,
        "message" => "Method not found: #{method}"
      }
    }
  end

  # Notifications (no id) - ignore
  defp handle_message(%{"jsonrpc" => "2.0", "method" => _method}) do
    nil
  end

  defp handle_message(_) do
    nil
  end

  # Tool implementations

  defp call_tool("e11y_check", args) do
    test_args = Map.get(args, "test_args", "")

    {output, exit_code} =
      if test_args == "" do
        System.cmd("mix", ["excessibility"], stderr_to_stdout: true)
      else
        cmd_args = String.split(test_args)
        System.cmd("mix", ["excessibility" | cmd_args], stderr_to_stdout: true)
      end

    %{
      "content" => [
        %{
          "type" => "text",
          "text" =>
            Jason.encode!(%{
              "status" => if(exit_code == 0, do: "success", else: "failure"),
              "exit_code" => exit_code,
              "output" => output
            })
        }
      ]
    }
  end

  defp call_tool("e11y_debug", args) do
    test_args = Map.get(args, "test_args", "")
    analyzers = Map.get(args, "analyzers")

    cmd_args = String.split(test_args)
    cmd_args = if analyzers, do: cmd_args ++ ["--analyze=#{analyzers}"], else: cmd_args

    {output, exit_code} =
      System.cmd("mix", ["excessibility.debug" | cmd_args], stderr_to_stdout: true)

    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    timeline_path = Path.join(base_path, "timeline.json")

    timeline =
      if File.exists?(timeline_path) do
        case File.read(timeline_path) do
          {:ok, content} -> Jason.decode!(content)
          _ -> nil
        end
      end

    %{
      "content" => [
        %{
          "type" => "text",
          "text" =>
            Jason.encode!(%{
              "status" => if(exit_code == 0, do: "success", else: "failure"),
              "exit_code" => exit_code,
              "output" => output,
              "timeline_path" => timeline_path,
              "timeline" => timeline
            })
        }
      ]
    }
  end

  defp call_tool("get_timeline", args) do
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    timeline_path = Map.get(args, "path") || Path.join(base_path, "timeline.json")

    result =
      if File.exists?(timeline_path) do
        case File.read(timeline_path) do
          {:ok, content} ->
            %{
              "status" => "success",
              "path" => timeline_path,
              "timeline" => Jason.decode!(content)
            }

          {:error, reason} ->
            %{
              "status" => "error",
              "error" => "Failed to read file: #{inspect(reason)}",
              "path" => timeline_path
            }
        end
      else
        %{
          "status" => "not_found",
          "error" => "Timeline file not found",
          "path" => timeline_path
        }
      end

    %{
      "content" => [
        %{
          "type" => "text",
          "text" => Jason.encode!(result)
        }
      ]
    }
  end

  defp call_tool("get_snapshots", args) do
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    snapshots_dir = Path.join(base_path, "html_snapshots")
    filter = Map.get(args, "filter", "*.html")
    include_content? = Map.get(args, "include_content", false)

    result =
      if File.dir?(snapshots_dir) do
        pattern = Path.join(snapshots_dir, filter)

        snapshots =
          pattern
          |> Path.wildcard()
          |> Enum.map(&build_snapshot(&1, include_content?))

        %{
          "status" => "success",
          "count" => length(snapshots),
          "snapshots" => snapshots
        }
      else
        %{
          "status" => "not_found",
          "error" => "Snapshots directory not found",
          "path" => snapshots_dir
        }
      end

    %{
      "content" => [
        %{
          "type" => "text",
          "text" => Jason.encode!(result)
        }
      ]
    }
  end

  defp call_tool(name, _args) do
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => Jason.encode!(%{"error" => "Unknown tool: #{name}"})
        }
      ],
      "isError" => true
    }
  end

  defp build_snapshot(path, include_content?) do
    snapshot = %{
      "filename" => Path.basename(path),
      "path" => path,
      "size" => File.stat!(path).size
    }

    if include_content? do
      Map.put(snapshot, "content", File.read!(path))
    else
      snapshot
    end
  end

  defp send_response(response) do
    json = Jason.encode!(response)
    IO.write(:stdio, json <> "\n")
  end

  defp send_error(code, message, id) do
    response = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => message
      }
    }

    send_response(response)
  end
end
