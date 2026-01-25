defmodule Excessibility.LiveViewHelpers do
  @moduledoc """
  Wrapper functions for Phoenix.LiveViewTest helpers that automatically
  capture snapshots when `@tag capture_snapshots: true` is used.
  """

  @doc """
  Wraps Phoenix.LiveViewTest.live/2 to capture initial render.
  """
  defmacro live(conn, path_or_action) do
    quote do
      result = Phoenix.LiveViewTest.live(unquote(conn), unquote(path_or_action))

      case result do
        {:ok, view, _html} ->
          if Excessibility.Capture.get_state() do
            Excessibility.Snapshot.html_snapshot(view, __ENV__, __MODULE__, event_type: "initial_render")
          end

        _ ->
          :ok
      end

      result
    end
  end

  @doc """
  Wraps Phoenix.LiveViewTest.render_click/1 to capture after click.
  """
  defmacro render_click(element) do
    quote do
      result = Phoenix.LiveViewTest.render_click(unquote(element))

      if Excessibility.Capture.get_state() do
        # Get the view from the element
        view = Excessibility.LiveViewHelpers.extract_view_runtime(unquote(element))

        if view do
          Excessibility.Snapshot.html_snapshot(view, __ENV__, __MODULE__, event_type: "click")
        end
      end

      result
    end
  end

  @doc """
  Wraps Phoenix.LiveViewTest.render_click/2 to capture after click.
  """
  defmacro render_click(element, value) do
    quote do
      result = Phoenix.LiveViewTest.render_click(unquote(element), unquote(value))

      if Excessibility.Capture.get_state() do
        view = Excessibility.LiveViewHelpers.extract_view_runtime(unquote(element))

        if view do
          Excessibility.Snapshot.html_snapshot(view, __ENV__, __MODULE__, event_type: "click")
        end
      end

      result
    end
  end

  @doc """
  Wraps Phoenix.LiveViewTest.render_change/2 to capture after change.
  """
  defmacro render_change(element_or_view, value) do
    quote do
      result = Phoenix.LiveViewTest.render_change(unquote(element_or_view), unquote(value))

      if Excessibility.Capture.get_state() do
        view = Excessibility.LiveViewHelpers.extract_view_runtime(unquote(element_or_view))

        if view do
          Excessibility.Snapshot.html_snapshot(view, __ENV__, __MODULE__, event_type: "change")
        end
      end

      result
    end
  end

  @doc """
  Wraps Phoenix.LiveViewTest.render_submit/2 to capture after submit.
  """
  defmacro render_submit(element_or_view, value) do
    quote do
      result = Phoenix.LiveViewTest.render_submit(unquote(element_or_view), unquote(value))

      if Excessibility.Capture.get_state() do
        view = Excessibility.LiveViewHelpers.extract_view_runtime(unquote(element_or_view))

        if view do
          Excessibility.Snapshot.html_snapshot(view, __ENV__, __MODULE__, event_type: "submit")
        end
      end

      result
    end
  end

  @doc """
  Wraps Phoenix.LiveViewTest.render/1 to just pass through.
  """
  defmacro render(view_or_element) do
    quote do
      Phoenix.LiveViewTest.render(unquote(view_or_element))
    end
  end

  @doc """
  Wraps Phoenix.LiveViewTest.element/2 to just pass through.
  """
  defmacro element(view_or_element, selector) do
    quote do
      Phoenix.LiveViewTest.element(unquote(view_or_element), unquote(selector))
    end
  end

  # Helper function to extract view from element or return as-is if already a view (runtime)
  def extract_view_runtime(%Phoenix.LiveViewTest.Element{proxy: {ref, topic, _}}),
    do: %Phoenix.LiveViewTest.View{proxy: {ref, topic, nil}}

  def extract_view_runtime(%Phoenix.LiveViewTest.View{} = view), do: view
  def extract_view_runtime(_), do: nil
end
