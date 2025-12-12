defmodule Mix.Tasks.Excessibility.InstallTest do
  use ExUnit.Case

  alias Igniter.Mix.Task.Args
  alias Mix.Tasks.Excessibility.Install
  alias Rewrite.Source

  test "adds configuration to test helper" do
    igniter =
      [files: %{"test/test_helper.exs" => "ExUnit.start()\n"}]
      |> Igniter.Test.test_project()
      |> put_args(endpoint: "DemoWeb.Endpoint", test_helper: "test/test_helper.exs", skip_npm: true)
      |> Install.igniter()

    content = file_content(igniter, "test/test_helper.exs")

    assert content =~ "Application.put_env(:excessibility, :endpoint, DemoWeb.Endpoint)"
    assert content =~ "Application.put_env(:excessibility, :browser_mod, Wallaby.Browser)"
  end

  test "does not duplicate configuration" do
    initial =
      """
      ExUnit.start()
      Application.put_env(:excessibility, :endpoint, DemoWeb.Endpoint)
      """

    igniter =
      [files: %{"test/test_helper.exs" => initial}]
      |> Igniter.Test.test_project()
      |> put_args(endpoint: "DemoWeb.Endpoint", test_helper: "test/test_helper.exs", skip_npm: true)
      |> Install.igniter()

    content = file_content(igniter, "test/test_helper.exs")

    assert content
           |> String.split("Application.put_env(:excessibility, :endpoint, DemoWeb.Endpoint)")
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
