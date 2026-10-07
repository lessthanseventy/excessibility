defmodule DemoWeb.AccessibleLive do
  @moduledoc """
  The happy path: a small task manager that does things right, so a review of
  this page comes back clean. It's the reference to compare the `Messy*` pages
  against — same features, accessible implementation.

  Highlights: one `<h1>` and ordered headings, a properly `<label>`-ed input,
  an `aria-live` region so added tasks are announced, real `<button>`s with
  discernible text, an `aria-expanded` disclosure, and an `<img>` with `alt`.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:tasks, ["Write the migration", "Review the PR"])
     |> assign(:show_help?, false)
     |> assign(:status, "")}
  end

  @impl true
  def handle_event("add", %{"task" => task}, socket) when task != "" do
    {:noreply,
     socket
     |> update(:tasks, &(&1 ++ [task]))
     |> assign(:status, "Added task: #{task}")}
  end

  def handle_event("add", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_help", _params, socket) do
    {:noreply, update(socket, :show_help?, &(not &1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page">
      <h1>Tasks</h1>

      <img src="/images/logo.svg" alt="Demo project logo" width="80" height="80" />

      <section aria-labelledby="add-heading">
        <h2 id="add-heading">Add a task</h2>
        <form phx-submit="add">
          <label for="task">Task description</label>
          <input id="task" name="task" type="text" />
          <button type="submit">Add task</button>
        </form>
        <p class="visually-hidden" role="status" aria-live="polite">{@status}</p>
      </section>

      <section aria-labelledby="list-heading">
        <h2 id="list-heading">Your tasks</h2>
        <ul>
          <li :for={task <- @tasks}>{task}</li>
        </ul>
      </section>

      <section>
        <h2>Need help?</h2>
        <button type="button" phx-click="toggle_help" aria-expanded={to_string(@show_help?)} aria-controls="help">
          {if @show_help?, do: "Hide help", else: "Show help"}
        </button>
        <div :if={@show_help?} id="help">
          <p>Type a task and press “Add task”. New tasks are announced to screen readers.</p>
        </div>
      </section>
    </main>
    """
  end
end
