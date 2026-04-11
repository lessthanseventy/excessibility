defmodule Excessibility.LiveViewRules do
  @moduledoc """
  LiveView-aware accessibility rules.

  Runs a set of HTML-level checks that axe-core cannot perform because
  they depend on Phoenix-specific attributes (`phx-click`, `phx-submit`,
  `phx-debounce`, etc.). These rules complement axe-core rather than
  replace it — snapshot tests run **both** axe-core and these rules.

  On non-Phoenix HTML the rules are no-ops: if no `phx-*` attributes
  exist, no findings are produced.

  ## Usage

      {:ok, html} = File.read("snapshot.html")
      result = Excessibility.LiveViewRules.scan(html)

      for finding <- result.findings do
        IO.puts("[\#{finding.severity}] \#{finding.rule}: \#{finding.message}")
      end

  ## Options

    * `:disable` — list of rule ids to skip (default `[]`)
    * `:only` — if given, run only these rule ids (overrides `:disable`)

  ## Adding custom rules

  Register application-level rule modules via config:

      config :excessibility, custom_live_view_rules: [MyApp.Rules.CustomRule]

  See `Excessibility.LiveViewRules.Rule` for the behaviour.
  """

  alias Excessibility.LiveViewRules.Rule

  @rule_behaviour Rule

  @typedoc "The aggregate result of a LiveView rule scan."
  @type result :: %{findings: [Rule.finding()], rules_run: [atom()]}

  # ── Compile-time rule discovery ────────────────────────────────────

  rules_dir = Path.join([__DIR__, "live_view_rules", "rules"])

  rule_modules =
    rules_dir
    |> Path.join("*.ex")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      module_name = path |> Path.basename(".ex") |> Macro.camelize()
      Module.concat([Excessibility.LiveViewRules.Rules, module_name])
    end)

  # Ensure each module is compiled & implements the behaviour
  @builtin_rules Enum.filter(rule_modules, fn mod ->
                   case Code.ensure_compiled(mod) do
                     {:module, _} ->
                       behaviours = mod.__info__(:attributes)[:behaviour] || []
                       @rule_behaviour in behaviours

                     _ ->
                       false
                   end
                 end)

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Returns all registered rule modules (built-in + custom via config).
  """
  @spec rules() :: [module()]
  def rules do
    custom =
      :excessibility
      |> Application.get_env(:custom_live_view_rules, [])
      |> Enum.filter(&valid_rule?/1)

    (@builtin_rules ++ custom)
    |> Enum.uniq()
    |> Enum.sort_by(& &1.id())
  end

  @doc """
  Scan an HTML string and return findings from all enabled rules.

  Returns `%{findings: [...], rules_run: [rule_id, ...]}`. On a parse
  failure returns `%{findings: [], rules_run: []}`.
  """
  @spec scan(String.t(), keyword()) :: result()
  def scan(html, opts \\ []) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        rules = enabled_rules(opts)
        findings = Enum.flat_map(rules, & &1.check(tree, opts))
        %{findings: findings, rules_run: Enum.map(rules, & &1.id())}

      {:error, _reason} ->
        %{findings: [], rules_run: []}
    end
  end

  @doc """
  Like `scan/2`, but reads HTML from a file path.
  """
  @spec scan_file(Path.t(), keyword()) :: result()
  def scan_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, html} -> scan(html, opts)
      {:error, _} -> %{findings: [], rules_run: []}
    end
  end

  # ── Internals ──────────────────────────────────────────────────────

  defp enabled_rules(opts) do
    all = rules()

    cond do
      only = Keyword.get(opts, :only) ->
        Enum.filter(all, &(&1.id() in List.wrap(only)))

      disabled = Keyword.get(opts, :disable) ->
        disabled_ids = List.wrap(disabled)
        Enum.reject(all, &(&1.id() in disabled_ids))

      true ->
        Enum.filter(all, & &1.default_enabled?())
    end
  end

  defp valid_rule?(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        @rule_behaviour in behaviours

      _ ->
        false
    end
  end
end
