if Code.ensure_loaded?(Hermes.Server) do
  # Tool components must be defined before the server that uses them

  defmodule Excessibility.MCP.Tools.E11yCheck do
    @moduledoc """
    Run tests and/or Pa11y accessibility checks on HTML snapshots.

    Without arguments: Run Pa11y on all existing snapshots.
    With arguments: Run `mix test [args]`, then Pa11y on new snapshots.
    """

    use Hermes.Server.Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:test_args, :string, description: "Arguments to pass to mix test (optional)")
    end

    @impl true
    def execute(params, frame) do
      test_args = Map.get(params, "test_args", "")

      {output, exit_code} =
        if test_args == "" do
          System.cmd("mix", ["excessibility"], stderr_to_stdout: true)
        else
          args = String.split(test_args)
          System.cmd("mix", ["excessibility" | args], stderr_to_stdout: true)
        end

      result = %{
        "status" => if(exit_code == 0, do: "success", else: "failure"),
        "exit_code" => exit_code,
        "output" => output
      }

      {:reply, Response.json(Response.tool(), result), frame}
    end
  end

  defmodule Excessibility.MCP.Tools.E11yDebug do
    @moduledoc """
    Run tests with telemetry capture and timeline analysis.

    Captures LiveView state evolution and runs analyzers to help debug issues.
    """

    use Hermes.Server.Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:test_args, {:required, :string}, description: "Arguments to pass to mix test (required)")

      field(:analyzers, :string, description: "Comma-separated list of analyzers to run")
      field(:format, :string, description: "Output format: markdown or json")
    end

    @impl true
    def execute(params, frame) do
      test_args = Map.fetch!(params, "test_args")
      analyzers = Map.get(params, "analyzers")
      format = Map.get(params, "format")

      args = String.split(test_args)
      args = if analyzers, do: args ++ ["--analyze=#{analyzers}"], else: args
      args = if format, do: args ++ ["--format=#{format}"], else: args

      {output, exit_code} =
        System.cmd("mix", ["excessibility.debug" | args], stderr_to_stdout: true)

      base_path =
        Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

      timeline_path = Path.join(base_path, "timeline.json")

      timeline =
        if File.exists?(timeline_path) do
          case File.read(timeline_path) do
            {:ok, content} -> Jason.decode!(content)
            _ -> nil
          end
        end

      result = %{
        "status" => if(exit_code == 0, do: "success", else: "failure"),
        "exit_code" => exit_code,
        "output" => output,
        "timeline_path" => timeline_path,
        "timeline" => timeline
      }

      {:reply, Response.json(Response.tool(), result), frame}
    end
  end

  defmodule Excessibility.MCP.Tools.GetTimeline do
    @moduledoc """
    Read the captured timeline showing LiveView state evolution.

    The timeline shows state at each event (mount, handle_event, render)
    with enrichments like memory size, duration, and changes.
    """

    use Hermes.Server.Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:path, :string, description: "Custom path to timeline.json (optional)")
    end

    @impl true
    def execute(params, frame) do
      base_path =
        Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

      timeline_path = Map.get(params, "path") || Path.join(base_path, "timeline.json")

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

      {:reply, Response.json(Response.tool(), result), frame}
    end
  end

  defmodule Excessibility.MCP.Tools.GetSnapshots do
    @moduledoc """
    List or read HTML snapshots captured during tests.

    Use to see what HTML was rendered, inspect specific components,
    or compare before/after states.
    """

    use Hermes.Server.Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:filter, :string, description: "Glob pattern to filter snapshots (e.g., '*_test_*.html')")

      field(:include_content, :boolean, description: "Include HTML content in response")
    end

    @impl true
    def execute(params, frame) do
      base_path =
        Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

      snapshots_dir = Path.join(base_path, "html_snapshots")
      filter = Map.get(params, "filter", "*.html")
      include_content? = Map.get(params, "include_content", false)

      result = build_snapshots_result(snapshots_dir, filter, include_content?)

      {:reply, Response.json(Response.tool(), result), frame}
    end

    defp build_snapshots_result(snapshots_dir, filter, include_content?) do
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
  end

  # Server module - uses the tools defined above
  defmodule Excessibility.MCP.Server do
    @moduledoc """
    MCP server providing excessibility tools for AI assistants.

    ## Tools

    - `e11y_check` - Run tests and/or Pa11y accessibility checks on HTML snapshots
    - `e11y_debug` - Run tests with telemetry capture and timeline analysis
    - `get_timeline` - Read the captured timeline showing LiveView state evolution
    - `get_snapshots` - List or read HTML snapshots captured during tests

    ## Usage

    Start the server with stdio transport:

        {:ok, _pid} = Hermes.Server.start_link(Excessibility.MCP.Server, [], transport: :stdio)

    Or add to your supervision tree:

        children = [
          {Excessibility.MCP.Server, transport: :stdio}
        ]

    ## Configuration

    The server reads the output path from application config:

        config :excessibility,
          excessibility_output_path: "test/excessibility"
    """

    use Hermes.Server,
      name: "excessibility",
      version: "0.9.0",
      capabilities: [:tools]

    component(Excessibility.MCP.Tools.E11yCheck)
    component(Excessibility.MCP.Tools.E11yDebug)
    component(Excessibility.MCP.Tools.GetTimeline)
    component(Excessibility.MCP.Tools.GetSnapshots)

    @impl true
    def init(_client_info, frame) do
      base_path =
        Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

      {:ok, assign(frame, base_path: base_path)}
    end
  end
end
