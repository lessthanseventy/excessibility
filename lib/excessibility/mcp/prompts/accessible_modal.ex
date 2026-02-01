defmodule Excessibility.MCP.Prompts.AccessibleModal do
  @moduledoc """
  MCP prompt for generating accessible Phoenix modal dialogs.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "accessible-modal"

  @impl true
  def description, do: "Generate an accessible modal dialog with focus trap, escape handling, and ARIA"

  @impl true
  def arguments do
    [
      %{
        "name" => "has_form",
        "description" => "Whether modal contains a form (default: false)",
        "required" => false
      },
      %{
        "name" => "size",
        "description" => "Modal size: 'small', 'medium', 'large' (default: 'medium')",
        "required" => false
      },
      %{
        "name" => "title",
        "description" => "Modal title for aria-labelledby",
        "required" => false
      },
      %{
        "name" => "dismissable",
        "description" => "Whether modal can be dismissed by clicking outside (default: true)",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    has_form? = Map.get(args, "has_form", "false") in ["true", true]
    size = Map.get(args, "size", "medium")
    title = Map.get(args, "title", "Dialog")
    dismissable? = Map.get(args, "dismissable", "true") in ["true", true]

    prompt_text = build_prompt(has_form?, size, title, dismissable?)

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

  defp build_prompt(has_form?, size, title, dismissable?) do
    """
    Generate an accessible Phoenix LiveView modal dialog with the following requirements:

    ## Modal Details
    - **Title**: #{title}
    - **Size**: #{size}
    - **Contains form**: #{if has_form?, do: "Yes", else: "No"}
    - **Click-outside dismissable**: #{if dismissable?, do: "Yes", else: "No (require explicit close)"}

    ## Accessibility Requirements

    ### Dialog Role and Labels
    - Use `role="dialog"` on the modal container
    - Add `aria-modal="true"` to indicate modal behavior
    - Use `aria-labelledby` pointing to the title element
    - Optionally use `aria-describedby` for description

    ### Focus Management
    - Focus must move INTO the modal when opened
    - Focus first interactive element or the close button
    - Return focus to trigger element when closed
    - Use Phoenix's `phx-mounted` hook for focus management

    ### Focus Trap
    - Focus must stay within modal while open
    - Tab and Shift+Tab should cycle through modal elements only
    - Implement focus trap with JavaScript hook

    ### Keyboard Navigation
    - Escape key must close the modal
    - Use `phx-window-keydown` with `phx-key="Escape"`
    #{if dismissable? do
      "- Click on backdrop closes modal"
    else
      "- Backdrop click does NOT close (form protection)"
    end}

    ### Background
    - Use backdrop/overlay behind modal
    - Add `aria-hidden="true"` to background content (or use `inert`)
    - Prevent background scrolling

    #{if has_form? do
      """
      ### Form Considerations
      - Warn before closing if form has unsaved changes
      - Submit button inside modal
      - Consider inline validation
      """
    else
      ""
    end}

    ## Code Template

    ```heex
    <div
      id="modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
      phx-window-keydown="close_modal"
      phx-key="Escape"
      phx-mounted={JS.focus_first()}
    >
      <!-- Backdrop -->
      <div
        class="modal-backdrop"
        #{if dismissable?, do: "phx-click=\"close_modal\"", else: ""}
        aria-hidden="true"
      />

      <!-- Dialog -->
      <div class="modal-content #{size_class(size)}" phx-click-away={#{if dismissable?, do: "\"close_modal\"", else: "nil"}}>
        <header>
          <h2 id="modal-title">#{title}</h2>
          <button
            phx-click="close_modal"
            aria-label="Close dialog"
            class="close-button"
          >
            <span aria-hidden="true">&times;</span>
          </button>
        </header>

        <div class="modal-body">
          #{if has_form?, do: "<!-- Form content -->", else: "<!-- Content -->"}
        </div>

        <footer>
          #{if has_form? do
      """
      <button type="button" phx-click="close_modal">Cancel</button>
      <button type="submit" form="modal-form">Save</button>
      """
    else
      """
      <button type="button" phx-click="close_modal">Close</button>
      """
    end}
        </footer>
      </div>
    </div>
    ```

    Include the JavaScript hook for focus trap and focus restoration.
    """
  end

  defp size_class("small"), do: "max-w-sm"
  defp size_class("large"), do: "max-w-4xl"
  defp size_class(_), do: "max-w-lg"
end
