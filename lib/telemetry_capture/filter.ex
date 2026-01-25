defmodule Excessibility.TelemetryCapture.Filter do
  @moduledoc """
  Filters noise from telemetry snapshot assigns.

  Removes Ecto metadata, Phoenix internals, function references,
  and other noise to improve signal-to-noise ratio for debugging.
  """

  @doc """
  Removes Ecto-related metadata from assigns.

  Filters out:
  - `__meta__` fields
  - `NotLoaded` associations
  """
  def filter_ecto_metadata(assigns) when is_map(assigns) do
    Enum.reduce(assigns, %{}, fn {key, value}, acc ->
      cond do
        key == :__meta__ -> acc
        is_struct(value) and value.__struct__ == Ecto.Association.NotLoaded -> acc
        is_map(value) and not is_struct(value) -> Map.put(acc, key, filter_ecto_metadata(value))
        is_list(value) -> Map.put(acc, key, Enum.map(value, &filter_ecto_metadata/1))
        true -> Map.put(acc, key, value)
      end
    end)

    # Skip __meta__ fields

    # Skip NotLoaded associations

    # Recursively filter maps

    # Recursively filter lists

    # Keep everything else
  end

  def filter_ecto_metadata(value) when is_list(value) do
    Enum.map(value, &filter_ecto_metadata/1)
  end

  def filter_ecto_metadata(value), do: value

  @phoenix_internal_keys [:flash, :__changed__, :__temp__]

  @doc """
  Removes Phoenix LiveView internal assigns.

  Filters out:
  - `:flash`, `:__changed__`, `:__temp__`
  - Keys starting with underscore (private assigns)
  """
  def filter_phoenix_internals(assigns) when is_map(assigns) do
    assigns
    |> Enum.reject(fn {key, _value} ->
      key in @phoenix_internal_keys or starts_with_underscore?(key)
    end)
    |> Map.new()
  end

  defp starts_with_underscore?(key) when is_atom(key) do
    key
    |> to_string()
    |> String.starts_with?("_")
  end

  defp starts_with_underscore?(_), do: false

  @doc """
  Removes function references from assigns.

  Functions can't be meaningfully serialized to JSON, and are typically
  internal implementation details not useful for debugging.

  Filters out:
  - Function values (callbacks, event handlers, socket refs)

  Recursively processes:
  - Structs (converted to maps)
  - Maps (non-struct)
  - Lists
  """
  def filter_functions(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> filter_functions()
  end

  def filter_functions(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> filter_functions()
  end

  def filter_functions(assigns) when is_map(assigns) do
    Enum.reduce(assigns, %{}, fn {key, value}, acc ->
      cond do
        is_function(value) ->
          acc

        is_struct(value) ->
          # Convert struct to map and filter recursively
          filtered =
            value
            |> Map.from_struct()
            |> filter_functions()

          Map.put(acc, key, filtered)

        is_map(value) ->
          Map.put(acc, key, filter_functions(value))

        is_tuple(value) ->
          Map.put(acc, key, filter_functions(value))

        is_list(value) ->
          Map.put(acc, key, filter_functions(value))

        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  def filter_functions(value) when is_list(value) do
    Enum.flat_map(value, fn item ->
      if is_function(item) do
        []
      else
        [filter_functions(item)]
      end
    end)
  end

  def filter_functions(value), do: value

  @doc """
  Applies all filtering to assigns based on options.

  ## Options

  - `:filter_ecto` - Remove Ecto metadata (default: true)
  - `:filter_phoenix` - Remove Phoenix internals (default: true)
  - `:filter_functions` - Remove function references (default: true)
  """
  def filter_assigns(assigns, opts \\ []) do
    filter_ecto? = Keyword.get(opts, :filter_ecto, true)
    filter_phoenix? = Keyword.get(opts, :filter_phoenix, true)
    filter_functions? = Keyword.get(opts, :filter_functions, true)

    assigns
    |> apply_if(filter_ecto?, &filter_ecto_metadata/1)
    |> apply_if(filter_phoenix?, &filter_phoenix_internals/1)
    |> apply_if(filter_functions?, &filter_functions/1)
  end

  defp apply_if(value, true, fun), do: fun.(value)
  defp apply_if(value, false, _fun), do: value
end
