defmodule Excessibility.ReleaseWorkflowTest do
  @moduledoc """
  Issue #187: static guards over the deliberate, human-gated release path. These
  assert `release.yml` keeps its safety invariants and that the CHANGELOG stays
  well-formed, so a future edit that quietly drops a guard fails loudly in CI
  rather than at (or after) a release.

  They are pure file reads — no git, network, or release side effects.
  """
  use ExUnit.Case, async: true

  @release_yml File.read!(".github/workflows/release.yml")
  @changelog File.read!("CHANGELOG.md")
  @mix_exs File.read!("mix.exs")

  describe "release.yml safety guards (#187)" do
    test "refuses any dispatch ref except the default branch" do
      assert @release_yml =~ ~s("$GITHUB_REF" != "refs/heads/main"),
             "release.yml must refuse to run for any ref other than refs/heads/main"
    end

    test "requires the release SHA to be the current tip of origin/main" do
      assert @release_yml =~ "git fetch --quiet origin main"
      assert @release_yml =~ "rev-parse origin/main"
    end

    test "verifies CI and Version Check succeeded for the exact release SHA" do
      assert @release_yml =~ "ci.yml"
      assert @release_yml =~ "version-check.yml"
      assert @release_yml =~ "head_sha=$sha"
      assert @release_yml =~ "status=success"
    end

    test "grants only the minimal actions: read scope for that verification" do
      assert @release_yml =~ ~r/permissions:.*actions:\s*read/s
    end

    test "does not gate the release on a reduced local mix test" do
      refute @release_yml =~ ~r/^\s*mix test\b/m,
             "the release must rely on verified exact-SHA CI (PostgreSQL + browser), not a reduced local `mix test`"
    end

    test "reruns resume: recreate the release when the tag already targets the SHA" do
      assert @release_yml =~ "create_tag=false"
      assert @release_yml =~ "gh release view"
      # A tag on any other SHA must still abort.
      assert @release_yml =~ ~r/not the release SHA/
    end

    test "never force-moves a tag" do
      for forbidden <- ["tag -f", "tag --force", "push -f", "push --force", "--force-with-lease"] do
        refute @release_yml =~ forbidden, "release.yml must never force-move a tag (found: #{forbidden})"
      end
    end

    test "enforces a dated, folded CHANGELOG before tagging" do
      # The version section must be dated...
      assert @release_yml =~ ~s(## \\[$VERSION\\] - [0-9]{4}-[0-9]{2}-[0-9]{2})
      # ...and [Unreleased] must be empty at release time.
      assert @release_yml =~ "[Unreleased]"
      assert @release_yml =~ ~r/still lists entries/
    end
  end

  describe "CHANGELOG well-formedness (#187)" do
    test "keeps an [Unreleased] section for in-flight work" do
      assert @changelog =~ ~r/^## \[Unreleased\]/m
    end

    test "every released version section carries an ISO date" do
      # Match `## [x.y.z]` headers that are NOT Unreleased; each must be dated.
      # A single documented legacy catch-all (`- Earlier`) predates dated
      # releases and is tolerated; every real version must be ISO-dated.
      version_headers =
        Regex.scan(~r/^## \[(?!Unreleased)([^\]]+)\][^\n]*/m, @changelog)

      assert version_headers != [], "expected at least one released version section"

      for [line, version] <- version_headers do
        assert line =~ ~r/- (\d{4}-\d{2}-\d{2}|Earlier)\s*$/,
               "CHANGELOG section for #{version} must be dated `## [#{version}] - YYYY-MM-DD` (got: #{inspect(line)})"
      end
    end

    test "the mix.exs @version has a changelog section" do
      [_, version] = Regex.run(~r/@version "([^"]+)"/, @mix_exs)

      assert @changelog =~ ~r/^## \[#{Regex.escape(version)}\]/m,
             "CHANGELOG.md must have a `## [#{version}]` section for the current mix.exs version"
    end
  end
end
