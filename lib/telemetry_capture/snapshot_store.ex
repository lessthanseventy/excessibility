defmodule Excessibility.TelemetryCapture.SnapshotStore do
  @moduledoc """
  Owns the `:excessibility_snapshots` ETS table so its lifetime is decoupled from
  any single test process.

  ETS tables are destroyed when their owner process dies. Previously the table
  was created by whichever process first called `Excessibility.TelemetryCapture.attach/0`
  — a test process. When that process finished (or another test's `attach/0` saw
  the table still owned by a *previous*, mid-teardown test process and therefore
  skipped creation), the table could vanish out from under a test still writing
  to it, surfacing intermittently as
  `ArgumentError: the table identifier does not refer to an existing ETS table`
  and a missing `timeline.json`.

  A dedicated, long-lived owner process holds the table for the whole VM/test run,
  so its existence no longer depends on test scheduling. The table stays
  `:public`, so every process reads and writes it exactly as before.
  """
  use GenServer

  @table :excessibility_snapshots

  @doc "The name of the ETS table this store owns."
  def table, do: @table

  @doc """
  Idempotently ensure the owner process (and therefore the ETS table) exist.

  Safe to call from any process, concurrently: the named `GenServer.start/3` is
  atomic, so exactly one owner is created and every other caller observes it as
  already started.
  """
  def ensure_started do
    case GenServer.start(__MODULE__, nil, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @impl true
  def init(nil) do
    # Own the table by creating it here. `ensure_started/0` is the only creator,
    # so on first start the table does not yet exist; tolerate a pre-existing
    # table (e.g. from a reload) by reusing it rather than crashing.
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :public, :bag])
    end

    {:ok, @table}
  end
end
