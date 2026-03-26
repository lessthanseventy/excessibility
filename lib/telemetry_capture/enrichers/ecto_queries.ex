defmodule Excessibility.TelemetryCapture.Enrichers.EctoQueries do
  @moduledoc """
  Enriches timeline events with Ecto query information.

  Provides two mechanisms:
  1. **Telemetry handler** — attaches to `[:ecto, :query]` events during test
     execution. Call `attach/0` before tests and `detach/0` after.
  2. **Enricher callback** — reads captured queries from opts or the query store.

  ## Example Output

      %{
        ecto_queries: [
          %{source: "products", operation: :select, duration_ms: 1.2, query: "SELECT..."}
        ],
        ecto_query_count: 2,
        ecto_total_query_ms: 2.0
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  @handler_id "excessibility-ecto-queries"

  @doc """
  Returns the enricher name.
  """
  def name, do: :ecto_queries

  @doc """
  Returns the cost of this enricher.
  """
  def cost, do: :moderate

  @doc """
  Enriches assigns with Ecto query data.

  Reads queries from the `:ecto_queries` key in opts.
  Returns query list, count, and total duration.
  """
  def enrich(_assigns, opts) do
    queries = Keyword.get(opts, :ecto_queries, [])

    total_ms =
      queries
      |> Enum.map(& &1.duration_ms)
      |> Enum.sum()

    %{
      ecto_queries: queries,
      ecto_query_count: length(queries),
      ecto_total_query_ms: Float.round(total_ms * 1.0, 2)
    }
  end

  # --- Telemetry handler ---

  @doc """
  Attaches a telemetry handler to `[:ecto, :query]` events.
  """
  def attach do
    :telemetry.attach(
      @handler_id,
      [:ecto, :query],
      &handle_query_event/4,
      nil
    )

    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Detaches the telemetry handler.
  """
  def detach do
    :telemetry.detach(@handler_id)
    :ok
  rescue
    _ -> :ok
  end

  defp handle_query_event(_event, measurements, metadata, _config) do
    duration_ms =
      case Map.get(measurements, :total_time) do
        nil -> 0.0
        native -> System.convert_time_unit(native, :native, :microsecond) / 1000
      end

    query_record = %{
      source: Map.get(metadata, :source, "unknown"),
      operation: extract_operation(Map.get(metadata, :query, "")),
      duration_ms: Float.round(duration_ms, 2),
      query: Map.get(metadata, :query, ""),
      repo: Map.get(metadata, :repo)
    }

    record_query(query_record)
  end

  defp extract_operation(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> case do
      "SELECT" -> :select
      "INSERT" -> :insert
      "UPDATE" -> :update
      "DELETE" -> :delete
      _ -> :other
    end
  end

  defp extract_operation(_), do: :other

  # --- Agent-based query store ---

  @doc """
  Starts the Agent-based query store.
  """
  def start_store do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc """
  Stops the query store.
  """
  def stop_store do
    if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    :ok
  end

  @doc """
  Records a query in the store.
  """
  def record_query(query_record) do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, &[query_record | &1])
    end
  end

  @doc """
  Returns all recorded queries in order.
  """
  def get_queries do
    if Process.whereis(__MODULE__) do
      Agent.get(__MODULE__, &Enum.reverse/1)
    else
      []
    end
  end

  @doc """
  Clears all recorded queries.
  """
  def clear do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn _ -> [] end)
    end
  end
end
