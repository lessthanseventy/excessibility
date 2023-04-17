defmodule ExcessibilityTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  @snapshots_path "test/excessibility/html_snapshots"

  describe "run/1" do
    test "when all pa11y checks pass" do
      Mix.Project.in_project(:test_pass, "test_pass/", fn _ ->
        refute capture_io(fn ->
                 Mix.Task.run("excessibility")
               end) =~
                 "Error:"
      end)
    end

    test "when a pa11y check fails" do
      Mix.Project.in_project(:test_fail, "test_fail/", fn _ ->
        assert capture_io(fn ->
                 Mix.Task.run("excessibility")
               end) =~
                 "Error:"
      end)
    end

    test "creates necessary directories for assets" do
      Mix.Project.in_project(:test_pass, "test_pass/", fn _ ->
        assert File.exists?("#{@snapshots_path}")
      end)
    end
  end
end
