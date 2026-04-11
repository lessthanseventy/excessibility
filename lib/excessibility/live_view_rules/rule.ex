defmodule Excessibility.LiveViewRules.Rule do
  @moduledoc """
  Behaviour for LiveView-aware accessibility rules.

  Each rule inspects a parsed HTML tree (from `Floki.parse_document!/1`)
  and returns zero or more findings describing accessibility issues that
  axe-core cannot detect on its own — typically because the issue
  depends on Phoenix-specific attributes like `phx-click`, `phx-submit`,
  `phx-debounce`, etc.

  Rules live under `lib/excessibility/live_view_rules/rules/` and are
  auto-discovered at compile time by `Excessibility.LiveViewRules`.

  ## Implementing a rule

      defmodule MyApp.Rules.CustomRule do
        @behaviour Excessibility.LiveViewRules.Rule

        @impl true
        def id, do: :custom_rule

        @impl true
        def default_enabled?, do: true

        @impl true
        def check(tree, _opts) do
          tree
          |> Floki.find("div[phx-click]")
          |> Enum.map(&build_finding/1)
        end

        defp build_finding(element), do: %{...}
      end

  Register custom rules via application config:

      config :excessibility, custom_live_view_rules: [MyApp.Rules.CustomRule]
  """

  @typedoc "Severity levels for LiveView rule findings."
  @type severity :: :critical | :serious | :moderate | :minor

  @typedoc "A single finding from a LiveView rule."
  @type finding :: %{
          rule: atom(),
          severity: severity(),
          message: String.t(),
          element: String.t(),
          selector: String.t(),
          help: String.t(),
          help_url: String.t() | nil
        }

  @doc "The unique identifier for this rule."
  @callback id() :: atom()

  @doc "Whether the rule runs by default. Can be overridden via config."
  @callback default_enabled?() :: boolean()

  @doc """
  Inspects the parsed HTML tree and returns any findings.

  `opts` is passed through from `Excessibility.LiveViewRules.scan/2` so
  rules can accept rule-specific options if needed.
  """
  @callback check(tree :: Floki.html_tree(), opts :: keyword()) :: [finding()]
end
