defmodule Excessibility.TelemetryCapture.Enrichers.Memory do
  @moduledoc """
  Enriches timeline events with memory size information.

  Calculates the byte size of assigns at each event by serializing
  to binary term format. This gives a proxy for memory usage.

  ## Usage

  Runs automatically during timeline building. Adds `:memory_size`
  field (in bytes) to each timeline event.

  ## Example Output

      %{
        sequence: 3,
        event: "handle_event:filter",
        memory_size: 45000,
        key_state: %{...}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  @doc """
  Returns the enricher name.
  """
  def name, do: :memory

  @doc """
  Enriches assigns with memory size.

  Serializes assigns to binary format and returns byte size.
  This provides a proxy for memory usage at this event.
  """
  def enrich(assigns, _opts) do
    size = calculate_size(assigns)
    %{memory_size: size}
  end

  defp calculate_size(assigns) do
    assigns
    |> :erlang.term_to_binary()
    |> byte_size()
  end
end
