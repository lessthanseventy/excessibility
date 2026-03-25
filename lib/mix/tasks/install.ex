defmodule Mix.Tasks.Excessibility.Install do
  @shortdoc "Installs Excessibility configuration into your project"
  @moduledoc """
  Installs Excessibility into a host project using Igniter.

  This task can be invoked directly or via `mix igniter.install excessibility`. It adds the
  recommended configuration to the target project's `config/test.exs` and (by default) runs
  `npm install` inside the vendored Excessibility assets directory to fetch axe-core dependencies.

  Requires Igniter to be installed in the host project.
  """
  use Igniter.Mix.Task

  alias Igniter.Libs.Phoenix
  alias Igniter.Mix.Task.Info
  alias Igniter.Project.Config
  alias Igniter.Project.Module, as: ProjectModule

  @impl true
  def info(_argv, _source) do
    %Info{
      group: :excessibility,
      schema: [
        endpoint: :string,
        head_render_path: :string,
        assets_dir: :string,
        skip_npm: :boolean,
        no_mcp: :boolean
      ],
      defaults: [skip_npm: false, head_render_path: "/", no_mcp: false],
      example: "mix excessibility.install --endpoint MyAppWeb.Endpoint"
    }
  end

  @impl true
  def igniter(igniter) do
    opts = igniter.args.options

    endpoint = fallback_endpoint(opts[:endpoint], igniter)
    head_render_path = opts[:head_render_path] || "/"
    assets_dir = opts[:assets_dir] || default_assets_dir()
    skip_npm? = opts[:skip_npm]
    skip_mcp? = opts[:no_mcp]

    igniter
    |> ensure_test_config(endpoint, head_render_path)
    |> ensure_test_helper()
    |> maybe_install_deps(assets_dir, skip_npm?)
    |> maybe_setup_claude_md()
    |> maybe_setup_mcp(skip_mcp?)
  end

  defp fallback_endpoint(nil, igniter) do
    igniter
    |> Phoenix.web_module()
    |> Module.concat("Endpoint")
  rescue
    _ -> "MyAppWeb.Endpoint"
  end

  defp fallback_endpoint(endpoint, _igniter) when is_binary(endpoint), do: ProjectModule.parse(endpoint)

  defp fallback_endpoint(module, _igniter), do: module

  defp ensure_test_config(igniter, endpoint, head_render_path) do
    igniter
    |> Config.configure("test.exs", :excessibility, [:endpoint], endpoint)
    |> Config.configure("test.exs", :excessibility, [:head_render_path], head_render_path)
    |> Config.configure("test.exs", :excessibility, [:browser_mod], Wallaby.Browser)
    |> Config.configure("test.exs", :excessibility, [:live_view_mod], Excessibility.LiveView)
    |> Config.configure("test.exs", :excessibility, [:system_mod], Excessibility.System)
  end

  defp ensure_test_helper(igniter) do
    test_helper_path = "test/test_helper.exs"

    telemetry_code = """
    # Enable Excessibility telemetry-based auto-capture for debugging
    # This is automatically enabled when running: mix excessibility.debug
    if System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true" do
      Excessibility.TelemetryCapture.attach()
    end
    """

    Igniter.update_file(igniter, test_helper_path, fn source ->
      content = Rewrite.Source.get(source, :content)

      if String.contains?(content, "Excessibility.TelemetryCapture.attach") do
        source
      else
        updated_content = inject_telemetry_code(content, telemetry_code)
        Rewrite.Source.update(source, :content, updated_content)
      end
    end)
  end

  defp inject_telemetry_code(content, telemetry_code) do
    if String.contains?(content, "ExUnit.start()") do
      String.replace(content, "ExUnit.start()", telemetry_code <> "\nExUnit.start()")
    else
      content <> "\n\n" <> telemetry_code
    end
  end

  defp maybe_install_deps(igniter, assets_dir, true), do: add_npm_notice(igniter, assets_dir)

  defp maybe_install_deps(igniter, assets_dir, _skip?) do
    package_json = Path.join(assets_dir, "package.json")

    cond do
      igniter.args.options[:dry_run] ->
        add_npm_notice(igniter, assets_dir)

      not File.exists?(package_json) ->
        Igniter.add_warning(
          igniter,
          "Could not find package.json inside #{assets_dir}. Skipping npm install."
        )

      true ->
        install_npm_and_playwright(igniter, assets_dir)
    end
  end

  defp install_npm_and_playwright(igniter, assets_dir) do
    Mix.shell().info("Installing npm packages in #{assets_dir}...")

    case System.cmd("npm", ["install"], cd: assets_dir, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        Mix.shell().info("✔ axe-core dependencies installed under #{assets_dir}")
        install_playwright_browser(igniter, assets_dir)

      {_, status} ->
        Igniter.add_warning(
          igniter,
          "npm install exited with status #{status}. Run it manually in #{assets_dir}."
        )
    end
  end

  defp install_playwright_browser(igniter, assets_dir) do
    Mix.shell().info("Installing Playwright Chromium browser...")

    case System.cmd("npx", ["playwright", "install", "chromium"],
           cd: assets_dir,
           into: IO.stream(:stdio, :line)
         ) do
      {_, 0} ->
        Mix.shell().info("✔ Playwright Chromium browser installed")
        igniter

      {_, status} ->
        Igniter.add_warning(
          igniter,
          "npx playwright install chromium exited with status #{status}. " <>
            "Run `npx playwright install chromium` manually in #{assets_dir}."
        )
    end
  end

  defp add_npm_notice(igniter, assets_dir) do
    Igniter.add_notice(
      igniter,
      "Run `npm install && npx playwright install chromium` inside #{assets_dir} to install axe-core dependencies."
    )
  end

  defp default_assets_dir do
    dep_path = Mix.Project.deps_paths()[:excessibility] || File.cwd!()
    Path.join(dep_path, "assets")
  end

  defp maybe_setup_claude_md(igniter) do
    claude_md_path = "CLAUDE.md"
    section = claude_md_section()

    if File.exists?(claude_md_path) do
      Igniter.update_file(igniter, claude_md_path, &append_claude_md_section(&1, section))
    else
      Igniter.create_or_update_file(igniter, claude_md_path, section, fn source -> source end)
    end
  end

  defp append_claude_md_section(source, section) do
    content = Rewrite.Source.get(source, :content)

    if String.contains?(content, "## Excessibility") do
      source
    else
      Rewrite.Source.update(source, :content, content <> "\n" <> section)
    end
  end

  @doc """
  Returns the CLAUDE.md section content for Excessibility.

  This section is appended to existing CLAUDE.md files or used as the initial
  content when creating a new one during installation.
  """
  def claude_md_section do
    """
    ## Excessibility

    ### Automatic Accessibility Checking

    After modifying any LiveView, controller, or template code, run the `check_work` MCP tool
    with the relevant test file before reporting work as complete. Fix critical violations
    before moving on.

    ```
    check_work(test_file: "test/my_app_web/live/page_live_test.exs")
    ```

    When working on performance-sensitive code or investigating LiveView state issues,
    include performance analysis:

    ```
    check_work(test_file: "test/my_app_web/live/page_live_test.exs", include_perf: true)
    ```

    ### Available Skills

    - `/e11y-tdd` — TDD workflow with html_snapshot and axe-core accessibility checking
    - `/e11y-debug` — Debug workflow with timeline analysis for LiveView state inspection
    - `/e11y-fix` — Reference guide for fixing WCAG violations with Phoenix-specific patterns

    ### MCP Tools

    - `check_work` — Run tests + a11y check + optional perf analysis (use this automatically)
    - `a11y_check` — Run axe-core accessibility checks on snapshots or URLs
    - `debug` — Run tests with telemetry capture, returns timeline data
    - `get_snapshots` — List or read HTML snapshots from tests
    - `get_timeline` — Read captured timeline data
    - `generate_test` — Generate test code with html_snapshot() calls
    """
  end

  # Skip MCP setup if --no-mcp flag is passed
  defp maybe_setup_mcp(igniter, true), do: igniter

  # By default, set up MCP server
  defp maybe_setup_mcp(igniter, _skip?) do
    if igniter.args.options[:dry_run] do
      add_mcp_manual_setup_notice(igniter)
    else
      igniter
      |> install_mcp_server()
      |> create_mcp_json()
      |> install_skills_plugin()
    end
  end

  defp install_mcp_server(igniter) do
    project_path = File.cwd!()

    Mix.shell().info("Setting up MCP server for Claude Code...")

    case System.cmd(
           "claude",
           [
             "mcp",
             "add",
             "excessibility",
             "-s",
             "project",
             "--",
             "mix",
             "run",
             "--no-halt",
             "-e",
             "Excessibility.MCP.Server.start()"
           ],
           cd: project_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        Mix.shell().info("✅ MCP server registered with Claude Code")

        if String.contains?(output, "already exists") do
          Mix.shell().info("   (server was already configured)")
        end

        igniter

      {output, _status} ->
        if String.contains?(output, "command not found") or String.contains?(output, "not found") do
          Igniter.add_warning(
            igniter,
            """
            Could not find 'claude' CLI. Install from: https://github.com/anthropics/claude-code

            Or manually add MCP server:
              claude mcp add excessibility -s project -- mix run --no-halt -e "Excessibility.MCP.Server.start()"
            """
          )
        else
          Igniter.add_warning(
            igniter,
            """
            MCP server registration failed: #{output}

            Manually add with:
              claude mcp add excessibility -s project -- mix run --no-halt -e "Excessibility.MCP.Server.start()"
            """
          )
        end
    end
  end

  defp create_mcp_json(igniter) do
    mcp_json_path = ".mcp.json"
    mcp_config = mcp_json_content()

    if File.exists?(mcp_json_path) do
      update_existing_mcp_json(igniter, mcp_json_path, mcp_config)
    else
      Igniter.create_or_update_file(igniter, mcp_json_path, mcp_config, fn source -> source end)
    end
  end

  defp update_existing_mcp_json(igniter, path, _new_config) do
    with {:ok, content} <- File.read(path),
         {:ok, existing} <- Jason.decode(content) do
      maybe_add_excessibility_server(igniter, path, existing)
    else
      {:error, %Jason.DecodeError{}} ->
        Igniter.add_warning(igniter, "Could not parse existing .mcp.json - skipping MCP config")

      {:error, _} ->
        igniter
    end
  end

  defp maybe_add_excessibility_server(igniter, path, existing) do
    servers = Map.get(existing, "mcpServers", %{})

    if Map.has_key?(servers, "excessibility") do
      igniter
    else
      updated = Map.put(existing, "mcpServers", Map.put(servers, "excessibility", mcp_server_entry()))
      Igniter.create_or_update_file(igniter, path, Jason.encode!(updated, pretty: true), fn source -> source end)
    end
  end

  defp mcp_server_entry do
    %{
      "command" => "deps/excessibility/bin/mcp-server",
      "args" => []
    }
  end

  defp mcp_json_content do
    Jason.encode!(%{"mcpServers" => %{"excessibility" => mcp_server_entry()}}, pretty: true)
  end

  defp install_skills_plugin(igniter) do
    dep_path = Mix.Project.deps_paths()[:excessibility] || File.cwd!()
    plugin_path = Path.join(dep_path, "priv/claude-plugin")

    if File.dir?(plugin_path) do
      do_install_skills_plugin(igniter, plugin_path)
    else
      igniter
    end
  end

  defp do_install_skills_plugin(igniter, plugin_path) do
    Mix.shell().info("Installing Claude Code skills plugin...")

    case System.cmd("claude", ["plugins", "add", plugin_path], stderr_to_stdout: true) do
      {output, 0} ->
        handle_plugin_success(igniter, output)

      {output, _status} ->
        handle_plugin_failure(igniter, output, plugin_path)
    end
  end

  defp handle_plugin_success(igniter, output) do
    Mix.shell().info("✅ Skills plugin installed (/e11y-tdd, /e11y-debug, /e11y-fix)")

    if String.contains?(output, "already installed") do
      Mix.shell().info("   (plugin was already installed)")
    end

    igniter
  end

  defp handle_plugin_failure(igniter, output, plugin_path) do
    not_found? =
      String.contains?(output, "command not found") or String.contains?(output, "not found")

    message =
      if not_found? do
        """
        Install skills plugin manually:
          claude plugins add #{plugin_path}
        """
      else
        """
        Skills plugin installation failed: #{output}

        Install manually:
          claude plugins add #{plugin_path}
        """
      end

    Igniter.add_notice(igniter, message)
  end

  defp add_mcp_manual_setup_notice(igniter) do
    dep_path = Mix.Project.deps_paths()[:excessibility] || File.cwd!()
    plugin_path = Path.join(dep_path, "priv/claude-plugin")

    Igniter.add_notice(
      igniter,
      """
      🔌 MCP Server Setup (dry run - run these manually):

      1. Add MCP server to Claude Code:
         claude mcp add excessibility -s project -- mix run --no-halt -e "Excessibility.MCP.Server.start()"

      2. Install skills plugin:
         claude plugins add #{plugin_path}

      Available tools: e11y_check, e11y_debug, get_timeline, get_snapshots
      Available skills: /e11y-tdd, /e11y-debug, /e11y-fix
      """
    )
  end
end
