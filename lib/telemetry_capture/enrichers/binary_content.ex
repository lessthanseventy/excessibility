defmodule Excessibility.TelemetryCapture.Enrichers.BinaryContent do
  @moduledoc """
  Enriches timeline events with information about large binary content.

  Detects large binaries in assigns that could cause memory issues:
  - Raw binary data (images, files)
  - Base64 encoded content
  - Binaries nested in maps and lists

  ## Options

  - `:binary_threshold` - Minimum size in bytes to flag (default: 10_000)

  ## Output

  Adds to each timeline event:
  - `binary_count` - Number of large binaries found
  - `total_binary_bytes` - Total size of all large binaries
  - `large_binaries` - List of binary info maps with:
    - `key` - The assign key (dot-notation for nested)
    - `size` - Size in bytes
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  @default_threshold 10_000

  @impl true
  def name, do: :binary_content

  @impl true
  def enrich(assigns, opts) do
    threshold = Keyword.get(opts, :binary_threshold, @default_threshold)
    binaries = find_large_binaries(assigns, threshold, [])

    %{
      binary_count: length(binaries),
      total_binary_bytes: Enum.sum(Enum.map(binaries, & &1.size)),
      large_binaries: binaries
    }
  end

  defp find_large_binaries(map, threshold, path) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      new_path = path ++ [key]
      find_large_binaries_in_value(value, threshold, new_path)
    end)
  end

  defp find_large_binaries(list, threshold, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, idx} ->
      new_path = path ++ [idx]
      find_large_binaries_in_value(value, threshold, new_path)
    end)
  end

  defp find_large_binaries(_other, _threshold, _path), do: []

  defp find_large_binaries_in_value(value, threshold, path) when is_binary(value) do
    size = byte_size(value)

    if size >= threshold do
      [%{key: path_to_key(path), size: size}]
    else
      []
    end
  end

  defp find_large_binaries_in_value(value, threshold, path) when is_map(value) do
    # Don't recurse into structs except for specific ones
    if is_struct(value) do
      []
    else
      find_large_binaries(value, threshold, path)
    end
  end

  defp find_large_binaries_in_value(value, threshold, path) when is_list(value) do
    find_large_binaries(value, threshold, path)
  end

  defp find_large_binaries_in_value(_value, _threshold, _path), do: []

  defp path_to_key([single]), do: single

  defp path_to_key(path) do
    path
    |> Enum.map_join(".", &to_string/1)
    |> String.to_atom()
  end
end
