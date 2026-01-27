defmodule Excessibility.TelemetryCapture.Enricher do
  @moduledoc """
  Behaviour for timeline event enrichers.

  Enrichers add computed data to timeline events during timeline building.
  All enrichers run automatically for every event.

  ## Example

      defmodule MyApp.CustomEnricher do
        @behaviour Excessibility.TelemetryCapture.Enricher

        def name, do: :custom

        def enrich(assigns, _opts) do
          %{custom_field: compute_value(assigns)}
        end
      end

  ## Callbacks

  - `name/0` - Returns atom identifier for this enricher
  - `enrich/2` - Takes assigns and options, returns map of fields to add to timeline event
  """

  @callback name() :: atom()
  @callback enrich(assigns :: map(), opts :: keyword()) :: map()
end
