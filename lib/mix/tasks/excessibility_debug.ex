defmodule Mix.Tasks.Excessibility.Debug do
  @shortdoc "Debug a test with comprehensive snapshot analysis"

  @moduledoc """
  Run a test and generate a comprehensive debug report with all snapshots.

  ## Usage

      mix excessibility.debug test/my_test.exs
      mix excessibility.debug test/my_test.exs --format=json
      mix excessibility.debug test/my_test.exs --format=package

  ## Formats

  - `markdown` (default) - Human and AI-readable report with inline HTML
  - `json` - Structured JSON output for programmatic parsing
  - `package` - Creates a directory with MANIFEST, timeline, and all snapshots

  ## Output

  The command outputs the report to stdout and also saves it to:
  - Markdown: `test/excessibility/latest_debug.md`
  - JSON: `test/excessibility/latest_debug.json`
  - Package: `test/excessibility/debug_packages/[test_name]_[timestamp]/`
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, test_paths, _} =
      OptionParser.parse(args,
        strict: [format: :string],
        aliases: [f: :format]
      )

    format = Keyword.get(opts, :format, "markdown")

    if test_paths == [] do
      Mix.shell().error("Usage: mix excessibility.debug test/path_test.exs")
      exit({:shutdown, 1})
    end

    test_path = List.first(test_paths)

    unless File.exists?(test_path) do
      Mix.shell().error("Test file not found: #{test_path}")
      exit({:shutdown, 1})
    end

    # Run the test and capture output
    {test_output, exit_code} = run_test(test_path)

    # Gather snapshots
    snapshots = gather_snapshots()

    # Build report based on format
    report_data = %{
      test_path: test_path,
      status: if(exit_code == 0, do: "passed", else: "failed"),
      test_output: test_output,
      snapshots: snapshots,
      timestamp: DateTime.utc_now()
    }

    case format do
      "json" ->
        output_json(report_data)

      "package" ->
        output_package(report_data)

      _ ->
        output_markdown(report_data)
    end
  end

  defp run_test(test_path) do
    # Enable telemetry capture
    System.put_env("EXCESSIBILITY_TELEMETRY_CAPTURE", "true")

    # Run the test and capture stdout/stderr
    result =
      System.cmd("mix", ["test", test_path],
        stderr_to_stdout: true,
        env: [
          {"MIX_ENV", "test"},
          {"EXCESSIBILITY_TELEMETRY_CAPTURE", "true"}
        ]
      )

    result
  end

  defp gather_snapshots do
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    snapshots_path = Path.join(output_path, "html_snapshots")

    if File.exists?(snapshots_path) do
      snapshots_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".html"))
      |> Enum.sort()
      |> Enum.map(fn filename ->
        path = Path.join(snapshots_path, filename)
        html = File.read!(path)

        # Extract metadata from HTML comment
        metadata = extract_metadata(html)

        %{
          filename: filename,
          path: path,
          html: html,
          metadata: metadata
        }
      end)
    else
      []
    end
  end

  defp extract_metadata(html) do
    # Extract metadata from HTML comment
    case Regex.run(~r/<!--\s*Excessibility Snapshot\s*(.*?)\s*-->/s, html) do
      [_, metadata_str] ->
        parse_metadata(metadata_str)

      _ ->
        %{}
    end
  end

  defp parse_metadata(metadata_str) do
    metadata_str
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key = key |> String.trim() |> String.downcase() |> String.replace(" ", "_")
          value = String.trim(value)
          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  defp output_markdown(report_data) do
    markdown = build_markdown_report(report_data)

    # Output to stdout
    Mix.shell().info(markdown)

    # Save to file
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    latest_path = Path.join(output_path, "latest_debug.md")
    File.mkdir_p!(output_path)
    File.write!(latest_path, markdown)

    Mix.shell().info("\n📋 Report saved to: #{latest_path}")
    Mix.shell().info("💡 Paste the above to Claude, or tell Claude to read #{latest_path}")
  end

  defp build_markdown_report(report_data) do
    status_emoji = if report_data.status == "passed", do: "✅", else: "❌"

    """
    # Test Debug Report: #{report_data.test_path}

    ## Test Result
    #{status_emoji} #{String.upcase(report_data.status)}

    ## Test Output
    ```
    #{report_data.test_output}
    ```

    ## Snapshots Generated (#{length(report_data.snapshots)})

    #{build_snapshots_section(report_data.snapshots)}

    ## Event Timeline

    #{build_timeline_section(report_data.snapshots)}

    ## Summary

    #{build_summary_section(report_data)}
    """
  end

  defp build_snapshots_section(snapshots) do
    snapshots
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {snapshot, index} ->
      """
      ### Snapshot #{index}: #{snapshot.filename}

      **Metadata:**
      #{format_metadata(snapshot.metadata)}

      **HTML:**
      ```html
      #{String.slice(snapshot.html, 0, 2000)}#{if String.length(snapshot.html) > 2000, do: "\n... (truncated)", else: ""}
      ```
      """
    end)
  end

  defp format_metadata(metadata) when map_size(metadata) == 0 do
    "- No metadata"
  end

  defp format_metadata(metadata) do
    Enum.map_join(metadata, "\n", fn {key, value} ->
      "- #{String.capitalize(String.replace(to_string(key), "_", " "))}: #{value}"
    end)
  end

  defp build_timeline_section([]), do: "No snapshots captured."

  defp build_timeline_section(snapshots) do
    Enum.map_join(snapshots, "\n", fn snapshot ->
      sequence = Map.get(snapshot.metadata, "sequence", "?")
      event = Map.get(snapshot.metadata, "event", "unknown")
      assigns = Map.get(snapshot.metadata, "assigns", "")

      "#{sequence}. #{event} → #{assigns}"
    end)
  end

  defp build_summary_section(report_data) do
    if report_data.status == "passed" do
      "All tests passed! Snapshots captured successfully."
    else
      "Test failed. Review the snapshots above to identify the issue."
    end
  end

  defp output_json(report_data) do
    json = Jason.encode!(report_data, pretty: true)

    Mix.shell().info(json)

    # Save to file
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    latest_path = Path.join(output_path, "latest_debug.json")
    File.mkdir_p!(output_path)
    File.write!(latest_path, json)
  end

  defp output_package(report_data) do
    test_name =
      report_data.test_path
      |> Path.basename(".exs")
      |> String.replace("_test", "")

    timestamp =
      report_data.timestamp
      |> DateTime.to_iso8601()
      |> String.replace(~r/[:\-]/, "")
      |> String.slice(0, 15)

    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    package_dir = Path.join([output_path, "debug_packages", "#{test_name}_#{timestamp}"])
    File.mkdir_p!(package_dir)

    # Create snapshots directory
    snapshots_dir = Path.join(package_dir, "snapshots")
    File.mkdir_p!(snapshots_dir)

    # Copy snapshots
    Enum.each(report_data.snapshots, fn snapshot ->
      dest = Path.join(snapshots_dir, snapshot.filename)
      File.write!(dest, snapshot.html)
    end)

    # Create timeline.json
    timeline = %{
      test: test_name,
      test_path: report_data.test_path,
      status: report_data.status,
      timestamp: report_data.timestamp,
      snapshots:
        Enum.map(report_data.snapshots, fn s ->
          Map.take(s, [:filename, :metadata])
        end)
    }

    timeline_path = Path.join(package_dir, "timeline.json")
    File.write!(timeline_path, Jason.encode!(timeline, pretty: true))

    # Create MANIFEST.md
    manifest = build_manifest(report_data, test_name)
    manifest_path = Path.join(package_dir, "MANIFEST.md")
    File.write!(manifest_path, manifest)

    Mix.shell().info("📦 Debug package created: #{package_dir}")
    Mix.shell().info("💡 Tell Claude: debug the package in #{package_dir}")
  end

  defp build_manifest(report_data, test_name) do
    status_emoji = if report_data.status == "passed", do: "✅", else: "❌"

    """
    # Debug Package: #{test_name}

    Generated: #{DateTime.to_string(report_data.timestamp)}
    Status: #{status_emoji} #{String.upcase(report_data.status)}

    ## Quick Summary

    #{build_summary_section(report_data)}

    ## Files

    - `timeline.json` - Complete event sequence with metadata
    - `snapshots/*.html` - DOM state at each step

    ## Event Sequence

    #{build_timeline_section(report_data.snapshots)}

    ## To Debug

    1. Read timeline.json for complete event flow
    2. Review snapshots in order
    3. Look for unexpected state changes or missing updates
    """
  end
end
