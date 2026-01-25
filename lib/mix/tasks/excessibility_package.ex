defmodule Mix.Tasks.Excessibility.Package do
  @moduledoc """
  Create a debug package for a test.

  This is an alias for `mix excessibility.debug --format=package`.

  ## Usage

      mix excessibility.package test/my_test.exs

  ## Description

  Creates a directory containing:
  - MANIFEST.md - Human-readable summary
  - timeline.json - Event sequence with metadata
  - snapshots/*.html - All captured snapshots

  The package is self-contained and can be easily shared with others or
  analyzed by AI tools like Claude.
  """

  use Mix.Task

  @shortdoc "Create a shareable debug package"

  @impl Mix.Task
  def run(args) do
    # Just delegate to excessibility.debug with --format=package
    Mix.Task.run("excessibility.debug", args ++ ["--format=package"])
  end
end
