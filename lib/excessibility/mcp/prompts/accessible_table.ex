defmodule Excessibility.MCP.Prompts.AccessibleTable do
  @moduledoc """
  MCP prompt for generating accessible Phoenix data tables.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "accessible-table"

  @impl true
  def description, do: "Generate an accessible data table with proper headers, caption, and optional sorting"

  @impl true
  def arguments do
    [
      %{
        "name" => "columns",
        "description" => "Comma-separated list of column names (e.g., 'Name, Email, Role, Actions')",
        "required" => true
      },
      %{
        "name" => "sortable",
        "description" => "Whether columns should be sortable (default: false)",
        "required" => false
      },
      %{
        "name" => "has_actions",
        "description" => "Whether to include action buttons column (default: true)",
        "required" => false
      },
      %{
        "name" => "caption",
        "description" => "Table caption/title for screen readers",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    columns = Map.get(args, "columns", "Name, Email, Actions")
    sortable? = Map.get(args, "sortable", "false") in ["true", true]
    has_actions? = Map.get(args, "has_actions", "true") in ["true", true]
    caption = Map.get(args, "caption")

    prompt_text = build_prompt(columns, sortable?, has_actions?, caption)

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

  defp build_prompt(columns, sortable?, has_actions?, caption) do
    column_list = columns |> String.split(",") |> Enum.map(&String.trim/1)

    """
    Generate an accessible Phoenix LiveView data table with the following requirements:

    ## Table Details
    - **Columns**: #{Enum.join(column_list, ", ")}
    - **Sortable**: #{if sortable?, do: "Yes - include sort controls", else: "No"}
    - **Actions column**: #{if has_actions?, do: "Yes - include edit/delete actions", else: "No"}
    #{if caption, do: "- **Caption**: #{caption}", else: ""}

    ## Accessibility Requirements

    ### Table Structure
    - Use semantic `<table>` element (not div-based grid)
    - Include `<caption>` for table title (can be visually hidden)
    - Use `<thead>` for header row
    - Use `<tbody>` for data rows
    - Use `<th scope="col">` for column headers
    - Use `<th scope="row">` for row headers if first column identifies the row

    ### Headers
    - Every column must have a `<th>` header
    - Headers must describe the column content clearly
    - For actions column, use "Actions" or visually hidden header

    #{if sortable? do
      """
      ### Sorting
      - Use `<button>` inside `<th>` for sort controls
      - Include `aria-sort="ascending"`, `"descending"`, or `"none"`
      - Provide visual sort indicator (arrow/icon)
      - Sort button text should be descriptive: "Sort by Name"
      """
    else
      ""
    end}

    ### Actions
    #{if has_actions? do
      """
      - Each action button must have accessible name
      - Use `aria-label` when button only has icon: `aria-label="Edit John Doe"`
      - Group related actions logically
      - Consider confirmation for destructive actions
      """
    else
      ""
    end}

    ### Responsive Considerations
    - Consider mobile layout (scrollable or stacked)
    - Maintain header associations on small screens
    - Use `scope` attribute to maintain cell-header relationships

    ## Code Template

    ```heex
    <table class="min-w-full">
      <caption class="sr-only">#{caption || "Data table"}</caption>
      <thead>
        <tr>
          #{Enum.map_join(column_list, "\n          ", fn col -> if sortable? do
        """
        <th scope="col">
          <button phx-click="sort" phx-value-column="#{Macro.underscore(col)}" aria-sort="none">
            #{col}
            <span class="sort-icon" aria-hidden="true"></span>
          </button>
        </th>
        """
      else
        "<th scope=\"col\">#{col}</th>"
      end end)}
        </tr>
      </thead>
      <tbody>
        <%= for item <- @items do %>
          <tr>
            <!-- Cell implementations -->
          </tr>
        <% end %>
      </tbody>
    </table>
    ```

    Provide complete implementation with proper Phoenix bindings.
    """
  end
end
