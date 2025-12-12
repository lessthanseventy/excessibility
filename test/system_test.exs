defmodule Excessibility.SystemTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Excessibility.System

  test "calls the correct OS command" do
    path = "/tmp/fake_path.html"

    assert capture_io(fn ->
             System.open_with_system_cmd(path)
           end) =~ ""
  end
end
