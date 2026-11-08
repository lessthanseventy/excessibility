defmodule Excessibility.Debug.Report do
  @moduledoc """
  Renders a `mix excessibility.debug` run as markdown, JSON, the digest, or a
  shareable package, and gathers the snapshots it reports on.
  """

  alias Excessibility.TelemetryCapture.Analyzer
  alias Excessibility.TelemetryCapture.Formatter
  alias Excessibility.TelemetryCapture.Registry
  alias Mix.Tasks.Excessibility.Debug

  def gather_snapshots do
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

  def output_markdown(report_data) do
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    timeline_path = Path.join(output_path, "timeline.json")

    # Get opts from process dictionary
    debug_opts = Process.get(:excessibility_debug_opts, %{})
    opts = Map.get(debug_opts, :filter_opts, [])

    # NEW: Run analyzers if timeline exists
    {markdown, _analysis_results} =
      if File.exists?(timeline_path) do
        timeline = timeline_path |> File.read!() |> Jason.decode!(keys: :atoms)

        # Run analyzers
        analyzer_names = Debug.parse_analyzer_selection(opts)
        analysis_results = run_analyzers(timeline, analyzer_names, opts)

        # Build markdown with analysis
        base_markdown = Formatter.format_markdown(timeline, report_data.snapshots)
        analysis_markdown = Formatter.format_analysis_results(analysis_results, opts)

        combined =
          if analysis_markdown == "" do
            base_markdown
          else
            base_markdown <> "\n\n---\n\n# Analysis Results\n\n" <> analysis_markdown
          end

        {combined, analysis_results}
      else
        {build_markdown_report(report_data), %{}}
      end

    # Output to stdout
    Mix.shell().info(markdown)

    # Save to file
    latest_path = Path.join(output_path, "latest_debug.md")
    File.mkdir_p!(output_path)
    File.write!(latest_path, markdown)

    Mix.shell().info("\n📋 Report saved to: #{latest_path}")
    Mix.shell().info("💡 Paste the above to Claude, or tell Claude to read #{latest_path}")
  end

  def output_json(report_data) do
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

  # Public (but @doc false) so the value-free digest output can be unit-tested
  # without shelling out through the full `run/1` test pipeline. The digest is
  # written during capture (see Excessibility.TelemetryCapture); this only reads
  # and prints it — it never rebuilds the digest.
  @doc false
  def output_digest(_report_data) do
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    digest_path = Path.join(output_path, "digest.json")

    if File.exists?(digest_path) do
      Mix.shell().info(File.read!(digest_path))
    else
      Mix.shell().info("No digest.json was produced at #{digest_path}.")

      Mix.shell().info(
        "The digest is only written when LiveView telemetry is captured. " <>
          "Run against a LiveView test, e.g. `mix excessibility.debug test/my_live_view_test.exs`."
      )
    end
  end

  def output_package(report_data) do
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

  defp run_analyzers(timeline, analyzer_names, opts) do
    analyzers =
      analyzer_names
      |> Enum.map(&Registry.get_analyzer/1)
      |> Enum.reject(&is_nil/1)

    # Sort by dependencies for correct execution order
    sorted_analyzers = Analyzer.sort_by_dependencies(analyzers)

    # Run analyzers in order, accumulating results for dependent analyzers
    {results, _} =
      Enum.reduce(sorted_analyzers, {%{}, %{}}, fn analyzer, {results, prior_results} ->
        # Pass prior results to analyzer
        analyzer_opts = Keyword.put(opts, :prior_results, prior_results)
        result = analyzer.analyze(timeline, analyzer_opts)

        # Accumulate results
        {
          Map.put(results, analyzer.name(), result),
          Map.put(prior_results, analyzer.name(), result)
        }
      end)

    results
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
end
