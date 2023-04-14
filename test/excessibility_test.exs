defmodule ExcessibilityTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  @output_path "test/excessibility"
  @snapshots_path "#{@output_path}/html_snapshots"
  @ex_assets_path "#{@output_path}/assets"

  describe "run/1" do
    @describetag :flipper
    test "when all pa11y checks pass" do
      Mix.Project.in_project(:test_pass, "test_pass/", fn _ ->
        assert capture_io(fn ->
                 Mix.Task.run("excessibility")
               end) =~
                 "Error:"
                 |> IO.inspect()
      end)
    end

    test "when a pa11y check fails" do
      Mix.Project.in_project(:test_fail, "test_fail/", fn _ ->
        assert capture_io(fn ->
                 Mix.Task.run("excessibility")
               end) =~
                 "Error:"
                 |> IO.inspect()
      end)
    end

    test "creates necessary directories for assets" do
      Mix.Project.in_project(:test_pass, "test_pass/", fn _ ->
        assert File.exists?("#{@ex_assets_path}/css")
        assert File.exists?("#{@ex_assets_path}/js")
      end)
    end
  end
end
