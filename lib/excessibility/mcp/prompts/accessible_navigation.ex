defmodule Excessibility.MCP.Prompts.AccessibleNavigation do
  @moduledoc """
  MCP prompt for generating accessible Phoenix navigation components.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "accessible-navigation"

  @impl true
  def description, do: "Generate accessible navigation with skip links, ARIA landmarks, and mobile support"

  @impl true
  def arguments do
    [
      %{
        "name" => "items",
        "description" => "Comma-separated navigation items (e.g., 'Home, Products, About, Contact')",
        "required" => true
      },
      %{
        "name" => "has_mobile",
        "description" => "Include mobile hamburger menu (default: true)",
        "required" => false
      },
      %{
        "name" => "has_dropdown",
        "description" => "Include dropdown submenu support (default: false)",
        "required" => false
      },
      %{
        "name" => "position",
        "description" => "Navigation position: 'header', 'sidebar', 'footer' (default: 'header')",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    items = Map.get(args, "items", "Home, About, Contact")
    has_mobile? = Map.get(args, "has_mobile", "true") in ["true", true]
    has_dropdown? = Map.get(args, "has_dropdown", "false") in ["true", true]
    position = Map.get(args, "position", "header")

    prompt_text = build_prompt(items, has_mobile?, has_dropdown?, position)

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

  defp build_prompt(items, has_mobile?, has_dropdown?, position) do
    item_list = items |> String.split(",") |> Enum.map(&String.trim/1)

    """
    Generate an accessible Phoenix LiveView navigation component with the following requirements:

    ## Navigation Details
    - **Items**: #{Enum.join(item_list, ", ")}
    - **Position**: #{position}
    - **Mobile menu**: #{if has_mobile?, do: "Yes - hamburger toggle", else: "No"}
    - **Dropdown submenus**: #{if has_dropdown?, do: "Yes", else: "No"}

    ## Accessibility Requirements

    ### Skip Link
    - Include "Skip to main content" link as FIRST focusable element
    - Link should be visually hidden until focused
    - Target should be `#main-content` or similar

    ```heex
    <a href="#main-content" class="sr-only focus:not-sr-only focus:absolute ...">
      Skip to main content
    </a>
    ```

    ### Landmark Roles
    - Use `<nav>` element with `aria-label="#{nav_label(position)}"`
    - Multiple navs need unique labels: "Main navigation", "Footer navigation"
    - Use `<header>`, `<main>`, `<footer>` landmarks appropriately

    ### Navigation Structure
    - Use `<ul>` and `<li>` for navigation lists
    - Current page link should have `aria-current="page"`
    - Links should have descriptive text (not just "Click here")

    #{if has_mobile? do
      """
      ### Mobile Menu
      - Toggle button with `aria-expanded="true/false"`
      - Button should have accessible label: "Open menu" / "Close menu"
      - Menu should have `aria-hidden` matching collapsed state
      - Use `aria-controls` to associate button with menu

      ```heex
      <button
        phx-click="toggle_menu"
        aria-expanded={@menu_open}
        aria-controls="mobile-menu"
        aria-label={if @menu_open, do: "Close menu", else: "Open menu"}
      >
        <span class="sr-only">Menu</span>
        <!-- Hamburger icon -->
      </button>

      <div id="mobile-menu" aria-hidden={not @menu_open}>
        <!-- Mobile nav items -->
      </div>
      ```
      """
    else
      ""
    end}

    #{if has_dropdown? do
      """
      ### Dropdown Submenus
      - Parent item should be a button with `aria-expanded`
      - Submenu should be a nested `<ul>`
      - Arrow keys navigate within dropdown
      - Escape closes dropdown
      - Click outside closes dropdown

      ```heex
      <li>
        <button
          phx-click="toggle_dropdown"
          aria-expanded={@dropdown_open}
          aria-haspopup="true"
        >
          Products
          <span aria-hidden="true">▼</span>
        </button>
        <ul :if={@dropdown_open} role="menu">
          <li role="menuitem"><a href="/products/widgets">Widgets</a></li>
          <li role="menuitem"><a href="/products/gadgets">Gadgets</a></li>
        </ul>
      </li>
      ```
      """
    else
      ""
    end}

    ### Keyboard Navigation
    - Tab navigates between top-level items
    #{if has_dropdown?, do: "- Arrow keys navigate within dropdowns", else: ""}
    - Enter/Space activates links and buttons
    #{if has_dropdown?, do: "- Escape closes open dropdowns", else: ""}

    ### Focus Indicators
    - Visible focus outline on all interactive elements
    - Don't remove `:focus` styles
    - Consider `:focus-visible` for keyboard-only focus

    ## Code Template

    ```heex
    <a href="#main-content" class="sr-only focus:not-sr-only ...">
      Skip to main content
    </a>

    <nav aria-label="#{nav_label(position)}">
      #{if has_mobile?, do: "<!-- Mobile toggle button -->", else: ""}

      <ul class="nav-list">
        #{Enum.map_join(item_list, "\n        ", fn item -> "<li><a href=\"/#{Macro.underscore(item)}\" aria-current={if @current_page == \"#{Macro.underscore(item)}\", do: \"page\"}>#{item}</a></li>" end)}
      </ul>
    </nav>
    ```

    Provide complete implementation with proper Phoenix bindings and responsive CSS.
    """
  end

  defp nav_label("header"), do: "Main navigation"
  defp nav_label("sidebar"), do: "Sidebar navigation"
  defp nav_label("footer"), do: "Footer navigation"
  defp nav_label(_), do: "Navigation"
end
