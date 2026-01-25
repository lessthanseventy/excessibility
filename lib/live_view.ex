defmodule Excessibility.LiveView do
  @moduledoc """
  LiveView HTML extraction for snapshot testing.

  Renders `Phoenix.LiveViewTest.View` and `Phoenix.LiveViewTest.Element`
  structs to HTML for accessibility testing.

  This module communicates with the LiveView test proxy to extract the
  current rendered HTML, including all nested LiveView components.

  ## Usage

  This module is used automatically when you call `html_snapshot/2` with
  a LiveView test view or element. You typically don't need to call it directly.

  ## Configuration

  Can be mocked via the `:live_view_mod` config key:

      Application.put_env(:excessibility, :live_view_mod, MyMockLiveView)
  """
  @behaviour Excessibility.LiveView.Behaviour

  alias Phoenix.LiveViewTest.Element, as: LiveElement
  alias Phoenix.LiveViewTest.View

  @doc """
  Renders a LiveView test view or element to HTML.

  ## Parameters

  - `view` - A `Phoenix.LiveViewTest.View` or `Phoenix.LiveViewTest.Element`

  ## Returns

  The rendered HTML as a Floki-parsed tree.
  """
  @impl true
  def render_tree(%View{} = view) do
    render_tree(view, {proxy_topic(view), "render", view.target})
  end

  def render_tree(%LiveElement{} = element) do
    render_tree(element, element)
  end

  def render_tree(view_or_element, topic_or_element) do
    call(view_or_element, {:render_element, :find_element, topic_or_element})
  end

  @doc """
  Extracts assigns from a LiveView test view.

  Returns `{:ok, assigns}` if successful, `{:error, reason}` otherwise.
  """
  def get_assigns(%View{} = view) do
    # Call the LiveView process to get assigns
    assigns = call(view, :get_state)

    case assigns do
      %{assigns: a} when is_map(a) -> {:ok, a}
      _ -> {:error, :no_assigns}
    end
  rescue
    error -> {:error, error}
  end

  def get_assigns(_), do: {:error, :invalid_view}

  @doc false
  def call(view_or_element, tuple) do
    GenServer.call(proxy_pid(view_or_element), tuple, 30_000)
  catch
    :exit, {{:shutdown, {kind, opts}}, _} when kind in [:redirect, :live_redirect] ->
      {:error, {kind, opts}}

    :exit, {{exception, stack}, _} ->
      exit({{exception, stack}, {__MODULE__, :call, [view_or_element]}})
  else
    :ok -> :ok
    {:ok, result} -> result
    {:raise, exception} -> raise exception
  end

  @doc false
  def proxy_pid(%{proxy: {_ref, _topic, pid}}), do: pid
  @doc false
  def proxy_topic(%{proxy: {_ref, topic, _pid}}), do: topic
end

defmodule Excessibility.LiveView.Behaviour do
  @moduledoc """
  Behaviour for LiveView HTML rendering.

  Implement this behaviour to provide custom LiveView rendering logic,
  useful for testing or alternative rendering strategies.
  """
  @callback render_tree(any()) :: String.t()
end
