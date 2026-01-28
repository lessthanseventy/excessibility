defmodule Excessibility.TelemetryCapture.Enricher do
  @moduledoc """
  Behaviour for timeline event enrichers.

  Enrichers add computed data to timeline events during timeline building.
  All enrichers run automatically for every event.

  ## Example

      defmodule MyApp.CustomEnricher do
        @behaviour Excessibility.TelemetryCapture.Enricher

        def name, do: :custom
        def cost, do: :cheap

        def enrich(assigns, _opts) do
          %{custom_field: compute_value(assigns)}
        end
      end

  ## Callbacks

  - `name/0` - Returns atom identifier for this enricher
  - `enrich/2` - Takes assigns and options, returns map of fields to add to timeline event
  - `cost/0` - (optional) Returns `:cheap`, `:moderate`, or `:expensive` for filtering
  """

  @callback name() :: atom()
  @callback enrich(assigns :: map(), opts :: keyword()) :: map()
  @callback cost() :: :cheap | :moderate | :expensive

  @optional_callbacks cost: 0

  @doc """
  Returns the cost of an enricher, defaulting to :cheap if not defined.
  """
  def get_cost(enricher_module) do
    if function_exported?(enricher_module, :cost, 0) do
      enricher_module.cost()
    else
      :cheap
    end
  end
end
