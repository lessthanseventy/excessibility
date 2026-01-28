defmodule Excessibility.TelemetryCapture.Enrichers.BinaryContentTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.BinaryContent

  describe "name/0" do
    test "returns :binary_content" do
      assert BinaryContent.name() == :binary_content
    end
  end

  describe "enrich/2" do
    test "returns empty stats when no large binaries present" do
      assigns = %{user: "test", count: 5, small_string: "hello"}

      result = BinaryContent.enrich(assigns, [])

      assert result.binary_count == 0
      assert result.total_binary_bytes == 0
      assert result.large_binaries == []
    end

    test "detects large binary in assigns" do
      # 50KB binary
      large_binary = :crypto.strong_rand_bytes(50_000)
      assigns = %{image_data: large_binary, name: "test"}

      result = BinaryContent.enrich(assigns, [])

      assert result.binary_count == 1
      assert result.total_binary_bytes == 50_000
      assert length(result.large_binaries) == 1

      [binary_info] = result.large_binaries
      assert binary_info.key == :image_data
      assert binary_info.size == 50_000
    end

    test "ignores small binaries" do
      # Small string (under threshold)
      assigns = %{small: "hello world", medium: String.duplicate("a", 1000)}

      result = BinaryContent.enrich(assigns, [])

      # Default threshold is 10KB, so these should not be flagged
      assert result.large_binaries == []
    end

    test "detects multiple large binaries" do
      bin1 = :crypto.strong_rand_bytes(20_000)
      bin2 = :crypto.strong_rand_bytes(30_000)
      assigns = %{file1: bin1, file2: bin2, name: "test"}

      result = BinaryContent.enrich(assigns, [])

      assert result.binary_count == 2
      assert result.total_binary_bytes == 50_000
      assert length(result.large_binaries) == 2
    end

    test "detects base64 encoded content" do
      # Large base64 string (typical for embedded images)
      raw = :crypto.strong_rand_bytes(15_000)
      base64 = Base.encode64(raw)
      assigns = %{encoded_image: base64}

      result = BinaryContent.enrich(assigns, [])

      # Base64 is ~33% larger than raw
      assert result.binary_count == 1
      assert length(result.large_binaries) == 1
    end

    test "detects binaries nested in maps" do
      large_binary = :crypto.strong_rand_bytes(25_000)
      assigns = %{upload: %{data: large_binary, filename: "test.png"}}

      result = BinaryContent.enrich(assigns, [])

      assert result.binary_count == 1
      [binary_info] = result.large_binaries
      assert binary_info.key == :"upload.data"
    end

    test "detects binaries in lists" do
      bin1 = :crypto.strong_rand_bytes(15_000)
      bin2 = :crypto.strong_rand_bytes(20_000)
      assigns = %{files: [%{data: bin1}, %{data: bin2}]}

      result = BinaryContent.enrich(assigns, [])

      assert result.binary_count == 2
    end

    test "respects custom threshold option" do
      # 5KB binary
      binary = :crypto.strong_rand_bytes(5_000)
      assigns = %{data: binary}

      # Default threshold (10KB) - not flagged
      result1 = BinaryContent.enrich(assigns, [])
      assert result1.large_binaries == []

      # Custom threshold (1KB) - flagged
      result2 = BinaryContent.enrich(assigns, binary_threshold: 1_000)
      assert length(result2.large_binaries) == 1
    end
  end
end
