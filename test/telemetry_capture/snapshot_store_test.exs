defmodule Excessibility.TelemetryCapture.SnapshotStoreTest do
  use ExUnit.Case, async: false

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.SnapshotStore

  # Regression for the flaky ETS race: the snapshot table used to be owned by
  # whichever process first called attach/0, so that process exiting destroyed
  # the table out from under other tests still writing to it
  # (ArgumentError: the table identifier does not refer to an existing ETS table).
  test "snapshot table survives the process that attached exiting" do
    # Attach from a short-lived process, then let it die. Under the old ownership
    # the table was created by (and owned by) this task, so it would vanish here.
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
