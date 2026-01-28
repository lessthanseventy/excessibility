---
name: e11y-fix
description: Reference guide for fixing Pa11y/WCAG errors in Phoenix LiveView - maps common violations to Phoenix-specific fixes
---

# Excessibility Fix - Pa11y Error Reference

Quick reference for fixing Pa11y/WCAG errors in Phoenix LiveView applications.

## Debugging Workflow

1. Run `mix excessibility` to see Pa11y errors
2. Use `html_snapshot(view)` to capture the problematic state
3. Read snapshot file to see exact HTML
4. Apply fix from reference below
5. Re-run `mix excessibility` to verify

## Quick Reference

| Pa11y Error | WCAG Rule | Phoenix Fix |
|-------------|-----------|-------------|
| Form input without label | 1.3.1 | Add `<.label>` or `aria-label` |
| Missing alt text | 1.1.1 | Add `alt` attribute to `<img>` |
| Low contrast | 1.4.3 | Adjust Tailwind colors |
| Missing lang | 3.1.1 | Add `lang="en"` to `<html>` |
| Empty link | 2.4.4 | Add link text or `aria-label` |
| Missing heading structure | 1.3.1 | Use proper `<h1>`-`<h6>` hierarchy |
| No skip link | 2.4.1 | Add "Skip to content" link |

## Common Fixes by Category

### Forms

#### Input without label

**Error:** "Form element does not have a label"

```heex
<!-- Bad -->
<input type="text" name="email" />

<!-- Good: Using Phoenix form helpers -->
<.input field={@form[:email]} type="email" label="Email address" />

<!-- Good: Manual label -->
<label for="email">Email address</label>
<input type="text" name="email" id="email" />

<!-- Good: aria-label for icon-only -->
<input type="search" aria-label="Search" />
```

#### Form without submit button

**Note:** LiveView forms using `phx-submit` often don't need a visible submit button. Pa11y may flag this. You can:

1. Add a submit button (even if styled invisibly)
2. Configure pa11y.json to ignore this rule for specific forms
3. Use `aria-label` on the form to explain the interaction

```heex
<!-- phx-submit form with hidden submit -->
<form phx-submit="save">
  <.input field={@form[:name]} type="text" label="Name" />
  <button type="submit" class="sr-only">Submit</button>
</form>
```

#### Required fields

```heex
<.input
  field={@form[:email]}
  type="email"
  label="Email"
  required
/>

<!-- Renders with aria-required="true" -->
```

#### Error messages

```heex
<.input
  field={@form[:email]}
  type="email"
  label="Email"
  errors={@form[:email].errors}
/>

<!-- Errors should be associated via aria-describedby -->
```

### Images

#### Missing alt text

**Error:** "Image missing alt attribute"

```heex
<!-- Bad -->
<img src={@avatar_url} />

<!-- Good: Meaningful alt -->
<img src={@avatar_url} alt={"Profile picture of #{@user.name}"} />

<!-- Good: Decorative image (empty alt) -->
<img src="/images/decorative-line.png" alt="" />

<!-- Good: Icon with adjacent text -->
<span>
  <img src="/icons/star.svg" alt="" />
  Favorites
</span>
```

### Links

#### Empty link

**Error:** "Link text is empty"

```heex
<!-- Bad: Icon-only link -->
<.link navigate={~p"/settings"}>
  <.icon name="hero-cog-6-tooth" />
</.link>

<!-- Good: Add aria-label -->
<.link navigate={~p"/settings"} aria-label="Settings">
  <.icon name="hero-cog-6-tooth" />
</.link>

<!-- Good: Add screen reader text -->
<.link navigate={~p"/settings"}>
  <.icon name="hero-cog-6-tooth" />
  <span class="sr-only">Settings</span>
</.link>
```

#### Vague link text

**Error:** "Link text is vague" (e.g., "click here", "read more")

```heex
<!-- Bad -->
<.link navigate={~p"/article/#{@article.id}"}>Read more</.link>

<!-- Good: Descriptive text -->
<.link navigate={~p"/article/#{@article.id}"}>
  Read more about <%= @article.title %>
</.link>

<!-- Good: Use aria-label for context -->
<.link navigate={~p"/article/#{@article.id}"} aria-label={"Read more about #{@article.title}"}>
  Read more
</.link>
```

### Headings

#### Skipped heading level

**Error:** "Heading levels should only increase by one"

```heex
<!-- Bad: h1 then h3 -->
<h1>Page Title</h1>
<h3>Section</h3>

<!-- Good: Sequential levels -->
<h1>Page Title</h1>
<h2>Section</h2>
<h3>Subsection</h3>
```

#### Multiple h1s

**Error:** "Page should have exactly one h1"

```heex
<!-- Ensure only one h1 per page -->
<h1><%= @page_title %></h1>

<!-- Use h2 for section headings -->
<section>
  <h2>Features</h2>
</section>
```

### Color Contrast

#### Low contrast text

**Error:** "Color contrast is too low"

```heex
<!-- Check your Tailwind colors -->
<!-- Bad: gray-400 on white (3.5:1 ratio) -->
<p class="text-gray-400">Low contrast text</p>

<!-- Good: gray-600 on white (5.7:1 ratio) -->
<p class="text-gray-600">Better contrast text</p>

<!-- Good: gray-700 on white (8.6:1 ratio) -->
<p class="text-gray-700">High contrast text</p>
```

Common Tailwind fixes:
- `text-gray-400` → `text-gray-600` or darker
- `text-blue-400` → `text-blue-600` or darker
- For dark backgrounds, use `-100` or `-200` variants

### Modals/Dialogs

#### Modal accessibility

```heex
<div
  id="modal"
  role="dialog"
  aria-modal="true"
  aria-labelledby="modal-title"
>
  <h2 id="modal-title">Confirm Action</h2>
  <p>Are you sure?</p>
  <button phx-click="confirm">Yes</button>
  <button phx-click="cancel">No</button>
</div>
```

**Focus management:** Use `phx-mounted` to trap focus:

```elixir
# In your LiveView
def handle_event("open_modal", _, socket) do
  {:noreply,
   socket
   |> assign(:show_modal, true)
   |> push_event("focus-modal", %{})}
end
```

### Dynamic Content

#### Live regions for updates

```heex
<!-- Announce changes to screen readers -->
<div aria-live="polite" aria-atomic="true">
  <%= if @flash[:info] do %>
    <%= @flash[:info] %>
  <% end %>
</div>

<!-- For important alerts -->
<div role="alert">
  <%= @error_message %>
</div>
```

#### Loading states

```heex
<div aria-busy={@loading}>
  <%= if @loading do %>
    <span class="sr-only">Loading...</span>
    <.spinner />
  <% else %>
    <%= @content %>
  <% end %>
</div>
```

## Phoenix-Specific Notes

### Core Components

Phoenix 1.7+ includes accessible core components. Use them:

```heex
<.input />     <!-- Handles labels, errors, aria -->
<.button />    <!-- Proper button semantics -->
<.modal />     <!-- Focus management, aria -->
<.table />     <!-- Proper table structure -->
```

### LiveView Forms

```heex
<.simple_form for={@form} phx-submit="save">
  <.input field={@form[:email]} type="email" label="Email" />
  <.input field={@form[:password]} type="password" label="Password" />
  <:actions>
    <.button>Save</.button>
  </:actions>
</.simple_form>
```

### Flash Messages

Default Phoenix flashes are accessible. Don't break them:

```heex
<!-- Use the built-in flash component -->
<.flash_group flash={@flash} />
```

## pa11y.json Configuration

For legitimate false positives, configure `pa11y.json`:

```json
{
  "defaults": {
    "standard": "WCAG2AA",
    "runners": ["htmlcs"],
    "ignore": [
      "WCAG2AA.Principle1.Guideline1_3.1_3_1.H44.NotFormControl"
    ]
  }
}
```

Common ignore patterns for LiveView:
- Forms without visible submit buttons (phx-submit handles it)
- Dynamic content warnings during transitions

## Verification

After fixing:

```bash
# Run Pa11y on all snapshots
mix excessibility

# Check specific test
mix excessibility test/my_test.exs

# Verify with fresh snapshots
rm -rf test/excessibility/html_snapshots/*
mix test test/my_test.exs
mix excessibility
```
