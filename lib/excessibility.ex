defmodule Excessibility do
  @moduledoc """
  Documentation for `Excessibility`.
  """

  @doc """
  Using the Excessibility macro will require the file for you.

  ## Examples

      use Excessibility

  """

  defmacro __using__(_opts) do
    quote do
      require Excessibility
    end
  end

  @doc """
  The html_snapshot macro can be called to produce an HTML snapshot of any of the following:
    - A Phoenix Conn
    - A Wallaby Session
    - A LiveViewTest View
    - A LiveViewTest Element
  These snapshots can then be used later to run pa11y against by calling the mix task..It will return the thing that was passed in so that you can include it in a pipeline.
  You can optionally pass a second argument of true to open the file in your browser for development purposes.

  ## Examples

      iex> Excessibility.html_snapshot(source, opts \\ [])
          source
  """

  defmacro html_snapshot(source, opts \\ []) do
    quote do
      Excessibility.Snapshot.html_snapshot(unquote(source), __ENV__, __MODULE__, unquote(opts))
    end
  end
end
