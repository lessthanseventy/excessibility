defmodule Excessibility.TelemetryCapture.Analyzers.CodePointer do
  @moduledoc """
  Maps timeline events to likely source code locations.

  Helps LLMs and developers locate relevant callbacks.
  Uses event type and view_module to suggest where to look.

  Not enabled by default - run with `--analyze=code_pointer`.

  ## Output

      %{
        findings: [],
        stats: %{
          pointers: [
            %{
              event: "handle_event:save_form",
              module: MyApp.FormLive,
              likely_location: "def handle_event(\"save_form\", params, socket) in MyApp.FormLive"
            }
          ]
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :code_pointer
  def default_enabled?, do: false

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{pointers: []}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    pointers =
      timeline
      |> Enum.map(&build_pointer/1)
      |> Enum.uniq_by(& &1.likely_location)

    %{
      findings: [],
      stats: %{pointers: pointers}
    }
  end

  defp build_pointer(%{event: event} = entry) do
    module = Map.get(entry, :view_module)
    location = infer_location(event, module)

    %{
      event: event,
      module: module,
      likely_location: location
    }
  end

  defp infer_location("mount", module) do
    module_str = if module, do: " in #{inspect(module)}", else: ""
    "def mount(params, session, socket)#{module_str}"
  end

  defp infer_location("handle_params", module) do
    module_str = if module, do: " in #{inspect(module)}", else: ""
    "def handle_params(params, uri, socket)#{module_str}"
  end

  defp infer_location("handle_event:" <> event_name, module) do
    module_str = if module, do: " in #{inspect(module)}", else: ""
    "def handle_event(\"#{event_name}\", params, socket)#{module_str}"
  end

  defp infer_location("handle_info:" <> msg_type, module) do
    module_str = if module, do: " in #{inspect(module)}", else: ""
    "def handle_info(#{msg_type}, socket)#{module_str}"
  end

  defp infer_location("render", module) do
    module_str = if module, do: " in #{inspect(module)}", else: ""
    "def render(assigns)#{module_str} or ~H sigil"
  end

  defp infer_location(event, module) do
    module_str = if module, do: " in #{inspect(module)}", else: ""
    "#{event}#{module_str}"
  end
end
