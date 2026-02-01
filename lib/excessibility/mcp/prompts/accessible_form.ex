defmodule Excessibility.MCP.Prompts.AccessibleForm do
  @moduledoc """
  MCP prompt for generating accessible Phoenix form templates.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "accessible-form"

  @impl true
  def description, do: "Generate an accessible Phoenix form with labels, error handling, and ARIA attributes"

  @impl true
  def arguments do
    [
      %{
        "name" => "fields",
        "description" => "Comma-separated list of form fields (e.g., 'name, email, password')",
        "required" => true
      },
      %{
        "name" => "has_errors",
        "description" => "Whether to include error state handling (default: true)",
        "required" => false
      },
      %{
        "name" => "form_type",
        "description" => "Type of form: 'create', 'edit', 'search', 'login' (default: 'create')",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    fields = Map.get(args, "fields", "name, email")
    has_errors? = Map.get(args, "has_errors", "true") in ["true", true]
    form_type = Map.get(args, "form_type", "create")

    prompt_text = build_prompt(fields, has_errors?, form_type)

    {:ok,
     %{
       "messages" => [
         %{
           "role" => "user",
           "content" => %{
             "type" => "text",
             "text" => prompt_text
           }
         }
       ]
     }}
  end

  defp build_prompt(fields, has_errors?, form_type) do
    field_list = fields |> String.split(",") |> Enum.map(&String.trim/1)

    """
    Generate an accessible Phoenix LiveView form with the following requirements:

    ## Form Details
    - **Form type**: #{form_type}
    - **Fields**: #{Enum.join(field_list, ", ")}
    - **Error handling**: #{if has_errors?, do: "Include full error state handling", else: "Minimal error handling"}

    ## Accessibility Requirements

    ### Labels
    - Every input MUST have an associated `<label>` element
    - Use Phoenix's `<.input>` component with `label` prop when available
    - Labels must be visible (no placeholder-only inputs)

    ### Error Messages
    #{if has_errors? do
      """
      - Use `aria-describedby` to associate error messages with inputs
      - Error messages must be in a `<p>` or `<span>` with matching `id`
      - Include `aria-invalid="true"` on inputs with errors
      - Use `role="alert"` for dynamically appearing errors
      - Consider using `phx-feedback-for` for Phoenix form feedback
      """
    else
      "- Basic error display only"
    end}

    ### Required Fields
    - Mark required fields with `aria-required="true"`
    - Provide visual indicator (asterisk with sr-only explanation)

    ### Form Structure
    - Use `<fieldset>` and `<legend>` for related field groups
    - Submit button must be present and clearly labeled
    - Use `phx-submit` for LiveView forms

    ### Keyboard Navigation
    - Logical tab order (no positive tabindex)
    - Submit on Enter should work

    ## Code Template

    Provide the form using Phoenix HEEx syntax:

    ```heex
    <.form for={@form} phx-submit="submit" phx-change="validate">
      <!-- Field implementations here -->

      <.button type="submit">
        #{button_text(form_type)}
      </.button>
    </.form>
    ```

    Include any necessary CSS classes for error states and visually hidden text.
    """
  end

  defp button_text("create"), do: "Create"
  defp button_text("edit"), do: "Save Changes"
  defp button_text("search"), do: "Search"
  defp button_text("login"), do: "Sign In"
  defp button_text(_), do: "Submit"
end
