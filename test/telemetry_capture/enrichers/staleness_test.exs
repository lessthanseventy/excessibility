defmodule Excessibility.TelemetryCapture.Enrichers.StalenessTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.Staleness

  describe "name/0" do
    test "returns :staleness" do
      assert Staleness.name() == :staleness
    end
  end

  describe "enrich/2" do
    test "returns empty when no timestamp fields present" do
      assigns = %{user: "test", count: 5}

      result = Staleness.enrich(assigns, [])

      assert result.stale_data_count == 0
      assert result.stale_fields == []
    end

    test "detects stale updated_at timestamp" do
      # Data updated 2 hours ago
      old_time = DateTime.add(DateTime.utc_now(), -7200, :second)
      assigns = %{post: %{title: "Test", updated_at: old_time}}

      result = Staleness.enrich(assigns, [])

      assert result.stale_data_count == 1
      [stale] = result.stale_fields
      assert stale.key == :"post.updated_at"
      assert stale.age_seconds >= 7200
    end

    test "does not flag recent timestamps" do
      # Data updated 30 seconds ago
      recent_time = DateTime.add(DateTime.utc_now(), -30, :second)
      assigns = %{post: %{title: "Test", updated_at: recent_time}}

      result = Staleness.enrich(assigns, [])

      assert result.stale_data_count == 0
    end

    test "detects multiple stale timestamps" do
      old_time1 = DateTime.add(DateTime.utc_now(), -3600, :second)
      old_time2 = DateTime.add(DateTime.utc_now(), -7200, :second)

      assigns = %{
        user: %{last_seen_at: old_time1},
        cache: %{fetched_at: old_time2}
      }

      result = Staleness.enrich(assigns, [])

      assert result.stale_data_count == 2
    end

    test "detects inserted_at fields" do
      old_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      assigns = %{record: %{inserted_at: old_time}}

      result = Staleness.enrich(assigns, [])

      # inserted_at is creation time, less relevant for staleness
      # but still tracked for awareness
      assert result.timestamp_fields >= 1
    end

    test "handles NaiveDateTime" do
      old_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      assigns = %{data: %{synced_at: old_time}}

      result = Staleness.enrich(assigns, [])

      assert result.stale_data_count == 1
    end

    test "respects custom staleness threshold" do
      # 10 minutes ago
      time = DateTime.add(DateTime.utc_now(), -600, :second)
      assigns = %{data: %{updated_at: time}}

      # Default threshold (5 min = 300s) - flagged as stale
      result1 = Staleness.enrich(assigns, [])
      assert result1.stale_data_count == 1

      # Custom threshold (15 min = 900s) - not stale
      result2 = Staleness.enrich(assigns, staleness_threshold: 900)
      assert result2.stale_data_count == 0
    end

    test "tracks timestamp field locations" do
      time = DateTime.utc_now()

      assigns = %{
        user: %{updated_at: time},
        nested: %{deep: %{modified_at: time}}
      }

      result = Staleness.enrich(assigns, [])

      assert result.timestamp_fields >= 2
      keys = Enum.map(result.all_timestamps, & &1.key)
      assert :"user.updated_at" in keys
      assert :"nested.deep.modified_at" in keys
    end
  end
end
