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
      example: "mix igniter.install excessibility --endpoint MyAppWeb.Endpoint --head-render-path /login"
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
end
