defmodule Excessibility.TelemetryCapture.SnapshotStoreTest do
  use ExUnit.Case, async: false

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.SnapshotStore

  # The snapshot table must outlive whichever process called attach/0, or it
  # vanishes under other tests still writing to it
  # (ArgumentError: the table identifier does not refer to an existing ETS table).
  test "snapshot table survives the process that attached exiting" do
    # Attach from a short-lived process, then let it die; a table owned by that
    # task would vanish here.
    task = Task.async(fn -> TelemetryCapture.attach() end)
    Task.await(task)
    refute Process.alive?(task.pid)

    # The table still exists and is writable from an unrelated process.
    assert :ets.whereis(SnapshotStore.table()) != :undefined
    assert :ets.insert(SnapshotStore.table(), {{:regression, System.unique_integer()}, :ok})

    :ets.delete_all_objects(SnapshotStore.table())
  end

  test "ensure_started/0 is idempotent and keeps a single owner" do
    assert :ok = SnapshotStore.ensure_started()
    owner = Process.whereis(SnapshotStore)
    assert is_pid(owner)

    assert :ok = SnapshotStore.ensure_started()
    assert Process.whereis(SnapshotStore) == owner
  end
end
