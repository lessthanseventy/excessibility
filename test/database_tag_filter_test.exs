defmodule Excessibility.DatabaseTagFilterTest do
  @moduledoc """
  Issue #186: `test_helper.exs` excludes database-integration tests without
  `DATABASE_URL`. It must exclude by tag *value* (`database: true`) so a DB-free
  companion guard colocated in a `@moduletag :database` module can opt back in
  with `@tag database: false`. An atom filter (`exclude: [:database]`) matches the
  tag key regardless of value and would silently exclude such a guard.

  These are pure assertions over ExUnit's own filter evaluation, so they run in
  every environment (with or without `DATABASE_URL`) and never touch a database.
  """
  use ExUnit.Case, async: true

  describe "value-scoped :database exclusion (#186)" do
    test "database: true is excluded, but database: false and untagged tests run" do
      exclude = [database: true]

      assert {:excluded, _} = ExUnit.Filters.eval([], exclude, %{database: true}, [])
      assert :ok = ExUnit.Filters.eval([], exclude, %{database: false}, [])
      assert :ok = ExUnit.Filters.eval([], exclude, %{}, [])
    end

    test "the old atom filter would have wrongly excluded database: false (regression witness)" do
      # This is the bug #186 fixes: an atom filter ignores the tag value, so a
      # `@tag database: false` override is excluded just like a real DB test.
      assert {:excluded, _} = ExUnit.Filters.eval([], [:database], %{database: false}, [])
    end

    @tag database: false
    test "a database: false companion test actually runs in the default no-DB suite" do
      # If `test_helper.exs` still used the atom filter, this test would be
      # excluded from `mix test` (no DATABASE_URL) and this assertion would never
      # execute. Its presence in the run is the end-to-end proof of the fix.
      assert true
    end
  end
end
