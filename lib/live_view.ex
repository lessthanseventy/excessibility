defmodule Excessibility.LiveView do
  @moduledoc """
  Provides functions for working with Phoenix LiveView test structures.

  This module handles rendering LiveView trees and extracting proxy information
  from LiveView test views and elements, enabling accurate HTML snapshotting
  for accessibility testing.
  """
  alias Phoenix.LiveViewTest.View
  alias Phoenix.LiveViewTest.Element, as: LiveElement

  @behaviour Excessibility.LiveView.Behaviour

  def render_tree(%View{} = view) do
    render_tree(view, {proxy_topic(view), "render", view.target})
  end

  def render_tree(%LiveElement{} = element) do
    render_tree(element, element)
  end

  def render_tree(view_or_element, topic_or_element) do
    call(view_or_element, {:render_element, :find_element, topic_or_element})
  end

  def call(view_or_element, tuple) do
    try do
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
  end

  def proxy_pid(%{proxy: {_ref, _topic, pid}}), do: pid
  def proxy_topic(%{proxy: {_ref, topic, _pid}}), do: topic
end

defmodule Excessibility.LiveView.Behaviour do
  @callback render_tree(any()) :: String.t()
end
