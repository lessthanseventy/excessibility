defmodule Excessibility.MCP.Tools.ExplainIssue do
  @moduledoc """
  MCP tool for deep explanations of WCAG codes or analyzer findings.

  Provides detailed context including why an issue matters, Phoenix-specific
  patterns for fixing it, code examples, and related issues.
  """

  @behaviour Excessibility.MCP.Tool

  @impl true
  def name, do: "explain_issue"

  @impl true
  def description do
    "Get detailed explanation of a WCAG code or analyzer finding. " <>
      "Includes why it matters, Phoenix patterns for fixing it, and code examples."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "issue" => %{
          "type" => "string",
          "description" => "WCAG code (e.g., 'H37', 'H44') or analyzer finding (e.g., 'memory_leak', 'n_plus_one')"
        }
      },
      "required" => ["issue"]
    }
  end

  @impl true
  def execute(%{"issue" => issue}, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Looking up issue...", 0)

    normalized = normalize_issue(issue)
    explanation = get_explanation(normalized)

    if progress_callback, do: progress_callback.("Complete", 100)

    if explanation do
      {:ok, explanation}
    else
      {:ok,
       %{
         "issue" => issue,
         "title" => "Unknown issue",
         "why" => "No detailed explanation available for this issue code.",
         "phoenix_patterns" => [],
         "examples" => %{},
         "related" => [],
         "resources" => ["https://www.w3.org/WAI/WCAG21/quickref/"]
       }}
    end
  end

  def execute(_args, _opts) do
    {:error, "Missing required argument: issue"}
  end

  defp normalize_issue(issue) when is_binary(issue) do
    issue
    |> String.upcase()
    |> String.trim()
    |> extract_core_code()
  end

  defp extract_core_code(issue) do
    cond do
      # Extract H## from WCAG codes like "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37"
      String.contains?(issue, ".H") ->
        case Regex.run(~r/\.?(H\d+)/, issue) do
          [_, code] -> code
          _ -> issue
        end

      # Extract F## from WCAG codes
      String.contains?(issue, ".F") ->
        case Regex.run(~r/\.?(F\d+)/, issue) do
          [_, code] -> code
          _ -> issue
        end

      # Already a short code
      true ->
        issue
    end
  end

  defp get_explanation(issue) do
    wcag_explanations()[issue] || analyzer_explanations()[String.downcase(issue)]
  end

  defp wcag_explanations do
    %{
      "H37" => %{
        "issue" => "H37",
        "title" => "Images must have alt attributes",
        "wcag" => "1.1.1 Non-text Content (Level A)",
        "why" => """
        Screen readers cannot describe images without alt text. Users who are blind \
        or have low vision rely on alt text to understand image content. Without it, \
        they hear only "image" or the filename, losing context that may be essential \
        to understanding the page.
        """,
        "phoenix_patterns" => [
          "Use alt={@description} for dynamic images",
          "Use alt=\"\" for decorative images (empty string, not missing)",
          "Use <.image> component with required alt prop",
          "For complex images, use aria-describedby pointing to longer description"
        ],
        "examples" => %{
          "bad" => "<img src={@url} />",
          "good" => "<img src={@url} alt={@alt_text} />",
          "decorative" => "<img src=\"/border.png\" alt=\"\" role=\"presentation\" />"
        },
        "related" => ["H36", "H67", "F65"],
        "resources" => [
          "https://www.w3.org/WAI/WCAG21/Techniques/html/H37",
          "https://webaim.org/techniques/alttext/"
        ]
      },
      "H44" => %{
        "issue" => "H44",
        "title" => "Form inputs must have associated labels",
        "wcag" => "1.3.1 Info and Relationships (Level A), 3.3.2 Labels or Instructions (Level A)",
        "why" => """
        Labels tell users what information to enter in form fields. Screen reader \
        users hear the label when focused on an input. Without labels, users cannot \
        know what data is expected. Clicking a label also focuses/activates the \
        associated input, improving usability for motor-impaired users.
        """,
        "phoenix_patterns" => [
          "Use <.input field={@form[:name]} label=\"Name\" />",
          "Use <label for=\"input_id\"> with matching id on input",
          "For hidden labels, use sr-only CSS class or aria-label",
          "Group related inputs with <fieldset> and <legend>"
        ],
        "examples" => %{
          "bad" => """
          <input type="text" name="user[name]" />
          """,
          "good" => """
          <label for="user_name">Full Name</label>
          <input type="text" name="user[name]" id="user_name" />
          """,
          "phoenix" => """
          <.input field={@form[:name]} type="text" label="Full Name" />
          """
        },
        "related" => ["H65", "H71"],
        "resources" => [
          "https://www.w3.org/WAI/WCAG21/Techniques/html/H44",
          "https://webaim.org/techniques/forms/controls"
        ]
      },
      "H32" => %{
        "issue" => "H32",
        "title" => "Forms must have submit buttons",
        "wcag" => "3.2.2 On Input (Level A)",
        "why" => """
        Users need a clear way to submit form data. Without a submit button, users \
        may not know how to complete the form. Screen reader users may not realize \
        that pressing Enter submits the form. A visible button provides clear affordance.
        """,
        "phoenix_patterns" => [
          "Forms with phx-submit are valid (Pa11y may still flag - add to ignore list)",
          "Use <button type=\"submit\"> for explicit submit",
          "For single-input forms, ensure Enter key behavior is clear"
        ],
        "examples" => %{
          "bad" => """
          <form phx-submit="save">
            <input type="text" name="query" />
          </form>
          """,
          "good" => """
          <form phx-submit="save">
            <input type="text" name="query" />
            <button type="submit">Search</button>
          </form>
          """,
          "pa11y_ignore" => """
          # In pa11y.json, ignore for LiveView forms:
          { "ignore": ["WCAG2AA.Principle1.Guideline1_3.1_3_1.H32.2"] }
          """
        },
        "related" => ["G80"],
        "resources" => ["https://www.w3.org/WAI/WCAG21/Techniques/html/H32"]
      },
      "H57" => %{
        "issue" => "H57",
        "title" => "HTML element must have lang attribute",
        "wcag" => "3.1.1 Language of Page (Level A)",
        "why" => """
        The lang attribute tells assistive technologies what language the page \
        content is in. Screen readers use this to select the correct pronunciation \
        rules. Without it, a French screen reader might mispronounce English text \
        or vice versa, making content incomprehensible.
        """,
        "phoenix_patterns" => [
          "Set lang=\"en\" (or appropriate code) on <html> in root.html.heex",
          "Use lang={@locale} for dynamic language from assigns",
          "Use lang attribute on inline foreign language text"
        ],
        "examples" => %{
          "bad" => """
          <!DOCTYPE html>
          <html>
          """,
          "good" => """
          <!DOCTYPE html>
          <html lang="en">
          """,
          "dynamic" => """
          <html lang={@locale || "en"}>
          """
        },
        "related" => ["H58"],
        "resources" => ["https://www.w3.org/WAI/WCAG21/Techniques/html/H57"]
      },
      "F65" => %{
        "issue" => "F65",
        "title" => "Iframes must have title attributes",
        "wcag" => "2.4.1 Bypass Blocks (Level A), 4.1.2 Name, Role, Value (Level A)",
        "why" => """
        The title attribute describes the iframe content to screen reader users. \
        Without it, users hear only "frame" and cannot know what content is embedded. \
        This is especially important for third-party embeds like videos or maps.
        """,
        "phoenix_patterns" => [
          "Always add title attribute describing iframe content",
          "For dynamic embeds, pass title as a component prop",
          "Hide decorative iframes from AT with aria-hidden=\"true\""
        ],
        "examples" => %{
          "bad" => """
          <iframe src={@video_url}></iframe>
          """,
          "good" => """
          <iframe src={@video_url} title="Product demonstration video"></iframe>
          """
        },
        "related" => ["H64"],
        "resources" => ["https://www.w3.org/WAI/WCAG21/Techniques/failures/F65"]
      },
      "CONTRAST" => %{
        "issue" => "contrast",
        "title" => "Text must have sufficient color contrast",
        "wcag" => "1.4.3 Contrast (Minimum) (Level AA)",
        "why" => """
        Low contrast text is difficult to read for users with low vision, color \
        blindness, or in bright/dim environments. WCAG requires a contrast ratio \
        of at least 4.5:1 for normal text and 3:1 for large text (18pt+ or 14pt+ bold).
        """,
        "phoenix_patterns" => [
          "Test color combinations with WebAIM Contrast Checker",
          "Use CSS custom properties for consistent, accessible colors",
          "Provide high-contrast mode toggle for users who need it",
          "Don't rely on color alone to convey meaning"
        ],
        "examples" => %{
          "bad" => """
          .text-gray { color: #999; background: #fff; }  /* 2.85:1 ratio */
          """,
          "good" => """
          .text-gray { color: #595959; background: #fff; }  /* 7:1 ratio */
          """
        },
        "related" => ["G18", "G145"],
        "resources" => [
          "https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html",
          "https://webaim.org/resources/contrastchecker/"
        ]
      }
    }
  end

  defp analyzer_explanations do
    %{
      "memory_leak" => %{
        "issue" => "memory_leak",
        "title" => "Memory leak detected in LiveView",
        "why" => """
        Memory leaks in LiveView cause the process heap to grow continuously, \
        eventually causing OOM crashes or degraded performance. Common causes \
        include accumulating lists in assigns, keeping references to old data, \
        or not cleaning up subscriptions.
        """,
        "phoenix_patterns" => [
          "Use streams for large/growing lists instead of assigns",
          "Limit list size with Enum.take/2 or sliding window",
          "Clean up resources in handle_info(:terminate, ...)",
          "Avoid keeping full history; keep only what's displayed"
        ],
        "examples" => %{
          "bad" => """
          def handle_info({:new_item, item}, socket) do
            {:noreply, update(socket, :items, &[item | &1])}  # List grows forever
          end
          """,
          "good" => """
          def handle_info({:new_item, item}, socket) do
            {:noreply, stream_insert(socket, :items, item, limit: 100)}
          end
          """
        },
        "related" => ["data_growth", "assign_lifecycle"],
        "resources" => ["https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-streams"]
      },
      "n_plus_one" => %{
        "issue" => "n_plus_one",
        "title" => "N+1 query pattern detected",
        "why" => """
        N+1 queries occur when code executes one query to get a list, then N \
        additional queries to get related data for each item. This causes linear \
        database load growth and slow page renders. In LiveView, this often happens \
        in templates or on every mount.
        """,
        "phoenix_patterns" => [
          "Preload associations in the initial query",
          "Use Ecto.Query.preload/3 or Repo.preload/2",
          "For conditional loading, use Dataloader",
          "Cache expensive queries in assigns, not computed on render"
        ],
        "examples" => %{
          "bad" => """
          # In template - executes N queries
          <%= for post <- @posts do %>
            <%= post.author.name %>  <!-- Loads author each iteration -->
          <% end %>
          """,
          "good" => """
          # In mount/handle_params - executes 2 queries
          posts = Posts.list_posts() |> Repo.preload(:author)
          """
        },
        "related" => ["performance"],
        "resources" => ["https://hexdocs.pm/ecto/Ecto.Query.html#preload/3"]
      },
      "event_cascade" => %{
        "issue" => "event_cascade",
        "title" => "Event cascade detected",
        "why" => """
        Event cascades occur when one event triggers another, which triggers \
        another, creating a chain of rapid events. This wastes CPU, causes \
        unnecessary re-renders, and can make the UI feel laggy or unresponsive.
        """,
        "phoenix_patterns" => [
          "Batch related state changes into single assign update",
          "Use assign/3 to update multiple keys atomically",
          "Debounce rapid user input with phx-debounce",
          "Consolidate related handle_event clauses"
        ],
        "examples" => %{
          "bad" => """
          def handle_event("update_quantity", %{"qty" => qty}, socket) do
            socket = assign(socket, :quantity, qty)
            socket = assign(socket, :subtotal, calculate_subtotal(socket))
            socket = assign(socket, :total, calculate_total(socket))
            {:noreply, socket}
          end
          """,
          "good" => """
          def handle_event("update_quantity", %{"qty" => qty}, socket) do
            {:noreply,
             assign(socket,
               quantity: qty,
               subtotal: calculate_subtotal(qty, socket.assigns),
               total: calculate_total(qty, socket.assigns)
             )}
          end
          """
        },
        "related" => ["render_efficiency", "performance"],
        "resources" => []
      },
      "render_efficiency" => %{
        "issue" => "render_efficiency",
        "title" => "Wasted renders detected",
        "why" => """
        Wasted renders occur when a component re-renders but its output hasn't \
        changed. This wastes CPU on both server and client and can cause UI flicker. \
        Common causes include unstable assigns or re-computing values on every render.
        """,
        "phoenix_patterns" => [
          "Use :if and :for attributes to skip unnecessary subtrees",
          "Memoize expensive computations in assigns, not inline",
          "Split volatile and stable state into separate components",
          "Use phx-update=\"ignore\" for static content"
        ],
        "examples" => %{
          "bad" => """
          # Recomputes on every render
          <div><%= Enum.count(@items) %> items</div>
          """,
          "good" => """
          # Assign computed values in handle_*
          socket = assign(socket, item_count: Enum.count(items))
          # In template
          <div><%= @item_count %> items</div>
          """
        },
        "related" => ["performance", "assign_lifecycle"],
        "resources" => [
          "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-change-tracking"
        ]
      }
    }
  end
end
