defmodule Mix.Tasks.Excessibility.Install do
  @shortdoc "Installs Excessibility configuration into your project"
  @moduledoc """
  Installs Excessibility into a host project using Igniter.

  This task can be invoked directly or via `mix igniter.install excessibility`. It adds the
  recommended configuration to the target project's `config/test.exs` and (by default) runs
  `npm install` inside the vendored Excessibility assets directory to fetch Pa11y.

  Requires Igniter to be installed in the host project.
  """
  use Igniter.Mix.Task

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
        skip_npm: :boolean
      ],
      defaults: [skip_npm: false, head_render_path: "/"],
      example: "mix excessibility.install --endpoint MyAppWeb.Endpoint --head-render-path /login"
    }
  end

  @impl true
  def igniter(igniter) do
    opts = igniter.args.options

    endpoint = fallback_endpoint(opts[:endpoint], igniter)
    head_render_path = opts[:head_render_path] || "/"
    assets_dir = opts[:assets_dir] || default_assets_dir()
    skip_npm? = opts[:skip_npm]

    igniter
    |> ensure_test_config(endpoint, head_render_path)
    |> ensure_pa11y_config()
    |> maybe_install_pa11y(assets_dir, skip_npm?)
    |> maybe_create_claude_docs()
  end

  defp fallback_endpoint(nil, igniter) do
    igniter
    |> Igniter.Libs.Phoenix.web_module()
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

  defp ensure_pa11y_config(igniter) do
    Igniter.create_or_update_file(igniter, "pa11y.json", pa11y_config(), fn source ->
      # Don't overwrite existing config
      source
    end)
  end

  defp pa11y_config do
    """
    {
      "ignore": [
        "WCAG2AA.Principle3.Guideline3_2.3_2_2.H32.2"
      ]
    }
    """
  end

  defp maybe_install_pa11y(igniter, assets_dir, true), do: add_npm_notice(igniter, assets_dir)

  defp maybe_install_pa11y(igniter, assets_dir, _skip?) do
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
        Mix.shell().info("Installing npm packages in #{assets_dir}...")

        case System.cmd("npm", ["install"], cd: assets_dir, into: IO.stream(:stdio, :line)) do
          {_, 0} ->
            Mix.shell().info("✔ Pa11y installed under #{assets_dir}")
            igniter

          {_, status} ->
            Igniter.add_warning(
              igniter,
              "npm install exited with status #{status}. Run it manually in #{assets_dir}."
            )
        end
    end
  end

  defp add_npm_notice(igniter, assets_dir) do
    Igniter.add_notice(
      igniter,
      "Run `npm install` inside #{assets_dir} to install Pa11y dependencies."
    )
  end

  defp default_assets_dir do
    dep_path = Mix.Project.deps_paths()[:excessibility] || File.cwd!()
    Path.join(dep_path, "assets")
  end

  defp maybe_create_claude_docs(igniter) do
    claude_docs_path = ".claude_docs/excessibility.md"

    if File.exists?(claude_docs_path) do
      # Ask if they want to update
      Igniter.add_notice(
        igniter,
        """
        Found existing #{claude_docs_path}

        To update with latest Excessibility features, run:
        mix excessibility.setup_claude_docs
        """
      )
    else
      if File.exists?(".claude_docs") do
        # .claude_docs exists, create the file
        Igniter.create_or_update_file(igniter, claude_docs_path, claude_docs_content(), fn source ->
          # File exists, don't overwrite
          source
        end)
      else
        # Suggest creating .claude_docs
        Igniter.add_notice(
          igniter,
          """
          💡 Using Excessibility with Claude?

          Create .claude_docs/excessibility.md to teach Claude how to:
          - Use mix excessibility.debug for instant context
          - Automatically capture LiveView state changes
          - Analyze snapshots without manual file management

          Run: mix excessibility.setup_claude_docs
          """
        )
      end
    end
  end

  defp claude_docs_content do
    """
    # Excessibility - LLM Development Workflow

    Excessibility helps debug Phoenix apps by capturing HTML snapshots during tests.

    ## Quick Commands

    ### Debug a test
    ```bash
    mix excessibility.debug test/my_test.exs
    ```
    Runs test, captures snapshots, outputs complete debug report with inline HTML.

    ### Show latest debug session
    ```bash
    mix excessibility.latest
    ```
    Re-displays most recent debug without re-running test.

    ### Create shareable package
    ```bash
    mix excessibility.package test/my_test.exs
    ```
    Creates directory with MANIFEST, timeline, and all snapshots.

    ## In Tests

    ### Auto-capture snapshots
    ```elixir
    @tag capture_snapshots: true
    test "user flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#button") |> render_click()
      # Snapshots captured automatically at each step
    end
    ```

    ### Granular control
    ```elixir
    @tag capture: :clicks           # Only clicks
    @tag capture: [:initial, :final] # Just first and last
    @tag capture: :on_change        # Only when DOM changes
    ```

    ## Snapshot Metadata

    Every snapshot includes metadata as HTML comment:
    - Test name
    - Event sequence number
    - Event type (click, change, submit, etc.)
    - LiveView assigns at that moment
    - Timestamp
    - Previous/next snapshot references

    ## Typical Workflow

    1. User reports failing test
    2. You run: `mix excessibility.debug test/failing_test.exs`
    3. Paste the output here (or tell me to read latest_debug.md)
    4. I analyze snapshots and identify the issue
    5. I suggest fixes

    ## Why This Helps

    LLMs can't:
    - Run your Phoenix app
    - Attach debuggers
    - Use IEx.pry()
    - See what actually renders

    Snapshots give me the actual DOM output so I can reason about real
    behavior instead of guessing from documentation.

    ## Tips

    - Use descriptive test names - they become snapshot filenames
    - Enable `generate_timeline: true` for complex flows
    - The timeline.json shows state changes clearly
    - Metadata in snapshots shows LiveView assigns at each step
    """
  end
end
