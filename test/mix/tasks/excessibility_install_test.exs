defmodule Mix.Tasks.Excessibility.InstallTest do
  use ExUnit.Case

  alias Igniter.Mix.Task.Args
  alias Mix.Tasks.Excessibility.Install
  alias Rewrite.Source

  test "adds configuration to config/test.exs" do
    igniter =
      []
      |> Igniter.Test.test_project()
      |> put_args(endpoint: "DemoWeb.Endpoint", skip_npm: true, no_mcp: true)
      |> Install.igniter()

    content = file_content(igniter, "config/test.exs")

    assert content =~ "config :excessibility"
    assert content =~ "endpoint: DemoWeb.Endpoint"
    assert content =~ ~s|head_render_path: "/"|
    assert content =~ "browser_mod: Wallaby.Browser"
    assert content =~ "live_view_mod: Excessibility.LiveView"
    assert content =~ "system_mod: Excessibility.System"
  end

  test "uses custom head_render_path for apps with auth" do
    igniter =
      []
      |> Igniter.Test.test_project()
      |> put_args(endpoint: "DemoWeb.Endpoint", head_render_path: "/login", skip_npm: true, no_mcp: true)
      |> Install.igniter()

    content = file_content(igniter, "config/test.exs")

    assert content =~ ~s|head_render_path: "/login"|
  end

  test "does not duplicate configuration" do
    igniter =
      []
      |> Igniter.Test.test_project()
      |> put_args(endpoint: "DemoWeb.Endpoint", skip_npm: true, no_mcp: true)
      |> Install.igniter()
      # Run install again
      |> Install.igniter()

    content = file_content(igniter, "config/test.exs")

    # Should only have one endpoint config
    assert content
           |> String.split("endpoint:")
           |> length() == 2
  end

  defp put_args(igniter, opts) do
    args = %Args{options: opts, positional: [], argv: [], argv_flags: []}
    Map.put(igniter, :args, args)
  end

  defp file_content(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Source.get(:content)
  end
end
