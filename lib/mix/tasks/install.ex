defmodule Mix.Tasks.Excessibility.Install do
  @moduledoc """
  Installs Excessibility into a host project using Igniter.

  This task can be invoked directly or via `mix igniter.install excessibility`. It adds the
  recommended `Application.put_env/3` configuration to the target project's
  `test/test_helper.exs` and (by default) runs `npm install` inside the vendored Excessibility
  assets directory to fetch Pa11y.
  """
  use Igniter.Mix.Task

  alias Igniter.Mix.Task.Info
  alias Igniter.Project.Deps
  alias Igniter.Project.Module, as: ProjectModule
  alias Rewrite.Source

  @impl true
  def info(_argv, _source) do
    %Info{
      group: :excessibility,
      schema: [
        endpoint: :string,
        test_helper: :string,
        assets_dir: :string,
        skip_npm: :boolean
      ],
      defaults: [skip_npm: false],
      example: "mix igniter.install excessibility --endpoint MyAppWeb.Endpoint"
    }
  end

  @impl true
  def igniter(igniter) do
    opts = igniter.args.options

    endpoint =
      fallback_endpoint(opts[:endpoint], igniter)

    test_helper = opts[:test_helper] || "test/test_helper.exs"
    assets_dir = opts[:assets_dir] || default_assets_dir()
    skip_npm? = opts[:skip_npm]

    igniter
    |> ensure_test_helper_config(test_helper, endpoint)
    |> ensure_floki_dependency()
    |> maybe_install_pa11y(assets_dir, skip_npm?)
  end

  defp fallback_endpoint(nil, igniter) do
    igniter
    |> ProjectModule.module_name_prefix()
    |> Module.concat("Web.Endpoint")
  rescue
    _ -> "MyAppWeb.Endpoint"
  end

  defp fallback_endpoint(endpoint, _igniter) when is_binary(endpoint), do: ProjectModule.parse(endpoint)

  defp fallback_endpoint(module, _igniter), do: module

  defp ensure_test_helper_config(igniter, test_helper, endpoint) do
    snippet = config_snippet(endpoint)
    default_contents = "ExUnit.start()\n"

    Igniter.create_or_update_file(igniter, test_helper, default_contents, fn source ->
      content = Source.get(source, :content)

      if String.contains?(content, "Application.put_env(:excessibility") do
        source
      else
        content
        |> String.trim_trailing()
        |> Kernel.<>("\n\n" <> snippet <> "\n")
        |> then(&Source.update(source, :content, &1))
      end
    end)
  end

  defp config_snippet(endpoint_module) do
    endpoint = inspect(endpoint_module)

    """
    # Excessibility snapshot configuration
    Application.put_env(:excessibility, :endpoint, #{endpoint})
    Application.put_env(:excessibility, :browser_mod, Wallaby.Browser)
    Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveView)
    Application.put_env(:excessibility, :system_mod, Excessibility.System)
    """
  end

  defp ensure_floki_dependency(igniter) do
    Deps.add_dep(igniter, {:floki, "~> 0.28"}, on_exists: :skip)
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
