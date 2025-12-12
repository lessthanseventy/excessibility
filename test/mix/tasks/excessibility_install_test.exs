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

  test "adds floki dependency when missing" do
    igniter =
      Igniter.Test.test_project(files: %{"test/test_helper.exs" => "ExUnit.start()\n"})
      |> put_args(endpoint: "DemoWeb.Endpoint", test_helper: "test/test_helper.exs", skip_npm: true)
      |> Install.igniter()

    mix_content = file_content(igniter, "mix.exs")

    assert mix_content =~ "{:floki, \"~> 0.28\"}"
  end

  test "ensures igniter dependency is present with runtime false" do
    igniter =
      Igniter.Test.test_project(files: %{"test/test_helper.exs" => "ExUnit.start()\n"})
      |> put_args(endpoint: "DemoWeb.Endpoint", test_helper: "test/test_helper.exs", skip_npm: true)
      |> Install.igniter()

    mix_content = file_content(igniter, "mix.exs")

    assert mix_content =~ "{:igniter, \"~> 0.7\", runtime: false}"
  end

  test "upgrades floki dependency when previously test-only" do
    mix_file = """
    defmodule Demo.MixProject do
      use Mix.Project

      def project do
        [
          app: :demo,
          version: "0.1.0",
          elixir: "~> 1.14",
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          {:floki, "~> 0.28", only: :test}
        ]
      end
    end
    """

    igniter =
      Igniter.Test.test_project(files: %{
        "mix.exs" => mix_file,
        "test/test_helper.exs" => "ExUnit.start()\n"
      })
      |> put_args(endpoint: "DemoWeb.Endpoint", test_helper: "test/test_helper.exs", skip_npm: true)
      |> Install.igniter()

    mix_content = file_content(igniter, "mix.exs")

    assert mix_content =~ "{:floki, \"~> 0.28\"}"
    refute mix_content =~ "{:floki, \"~> 0.28\", only: :test}"
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
