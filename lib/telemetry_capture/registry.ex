defmodule Excessibility.TelemetryCapture.Registry do
  @moduledoc """
  Auto-discovers enrichers and analyzers at compile time.

  Built-in enrichers are discovered from `lib/telemetry_capture/enrichers/` and must
  implement the `Excessibility.TelemetryCapture.Enricher` behaviour.

  Built-in analyzers are discovered from `lib/telemetry_capture/analyzers/` and must
  implement the `Excessibility.TelemetryCapture.Analyzer` behaviour.

  ## Custom Plugins

  Users can register custom enrichers and analyzers via application config:

      # config/test.exs
      config :excessibility,
        custom_enrichers: [MyApp.CustomEnricher],
        custom_analyzers: [MyApp.CustomAnalyzer]

  Custom modules must implement the appropriate behaviour.

  ## Usage

      # Get all enrichers (built-in + custom)
      Registry.discover_enrichers()

      # Get analyzers that run by default
      Registry.get_default_analyzers()

      # Get specific analyzer by name
      Registry.get_analyzer(:memory)
  """

  @enricher_behaviour Excessibility.TelemetryCapture.Enricher
  @analyzer_behaviour Excessibility.TelemetryCapture.Analyzer

  # Compile-time discovery helper functions
  file_to_module = fn path, subdir ->
    module_name =
      path
      |> Path.basename(".ex")
      |> Macro.camelize()

    subdir_name = Macro.camelize(subdir)
    Module.concat([Excessibility.TelemetryCapture, subdir_name, module_name])
  end

  implements_behaviour? = fn module, behaviour ->
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        behaviour in behaviours

      {:error, _} ->
        false
    end
  end

  discover_modules = fn subdir, behaviour ->
    base_path = Path.join([__DIR__, subdir])

    base_path
    |> Path.join("*.ex")
    |> Path.wildcard()
    |> Enum.map(&file_to_module.(&1, subdir))
    |> Enum.filter(&implements_behaviour?.(&1, behaviour))
    |> Enum.sort_by(& &1.name())
  end

  # Built-in plugins discovered at compile time
  @builtin_enrichers discover_modules.("enrichers", @enricher_behaviour)
  @builtin_analyzers discover_modules.("analyzers", @analyzer_behaviour)

  @doc """
  Returns all registered enrichers (built-in + custom).

  Enrichers run automatically during timeline building.
  Custom enrichers can be configured via `:custom_enrichers` in app config.
  """
  def discover_enrichers do
    custom = Application.get_env(:excessibility, :custom_enrichers, [])
    valid_custom = Enum.filter(custom, &valid_enricher?/1)
    merge_plugins(@builtin_enrichers, valid_custom)
  end

  @doc """
  Returns all registered analyzers (built-in + custom).

  Custom analyzers can be configured via `:custom_analyzers` in app config.
  """
  def discover_analyzers do
    custom = Application.get_env(:excessibility, :custom_analyzers, [])
    valid_custom = Enum.filter(custom, &valid_analyzer?/1)
    merge_plugins(@builtin_analyzers, valid_custom)
  end

  @doc """
  Returns analyzers that are enabled by default.

  These run unless explicitly disabled via --no-analyze flag.
  """
  def get_default_analyzers do
    Enum.filter(discover_analyzers(), & &1.default_enabled?())
  end

  @doc """
  Returns all analyzers regardless of default_enabled? status.
  """
  def get_all_analyzers, do: discover_analyzers()

  @doc """
  Finds analyzer by name.

  Returns nil if not found.
  """
  def get_analyzer(name) do
    Enum.find(discover_analyzers(), fn analyzer ->
      analyzer.name() == name
    end)
  end

  # Validates that a module implements the Enricher behaviour
  defp valid_enricher?(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        @enricher_behaviour in behaviours

      {:error, _} ->
        false
    end
  end

  # Validates that a module implements the Analyzer behaviour
  defp valid_analyzer?(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        @analyzer_behaviour in behaviours

      {:error, _} ->
        false
    end
  end

  # Merges built-in and custom plugins, sorted by name, no duplicates
  defp merge_plugins(builtin, custom) do
    (builtin ++ custom)
    |> Enum.uniq()
    |> Enum.sort_by(& &1.name())
  end
end
