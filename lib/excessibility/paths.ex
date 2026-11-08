defmodule Excessibility.Paths do
  @moduledoc """
  Where Excessibility writes: the output root from `:excessibility_output_path`
  and the snapshot and baseline directories under it.
  """

  @default "test/excessibility"

  @doc "The output root: `test/excessibility` unless `:excessibility_output_path` says otherwise."
  @spec output_path() :: Path.t()
  def output_path, do: Application.get_env(:excessibility, :excessibility_output_path, @default)

  @doc "Where `html_snapshot/2` writes snapshots."
  @spec snapshots_dir() :: Path.t()
  def snapshots_dir, do: Path.join(output_path(), "html_snapshots")

  @doc "Where `mix excessibility.baseline` locks snapshots."
  @spec baseline_dir() :: Path.t()
  def baseline_dir, do: Path.join(output_path(), "baseline")
end
