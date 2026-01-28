defmodule MockSchema do
  @moduledoc false
  defstruct [:name, :email, :age]
end

defmodule Excessibility.TelemetryCapture.Enrichers.ChangesetTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.Changeset

  describe "name/0" do
    test "returns :changeset" do
      assert Changeset.name() == :changeset
    end
  end

  describe "enrich/2" do
    test "returns empty map when no changesets present" do
      assigns = %{user: "test", count: 5}

      result = Changeset.enrich(assigns, [])

      assert result == %{changeset_count: 0, changesets: []}
    end

    test "detects changeset in assigns" do
      changeset = build_changeset(%{name: "test"}, %{name: "updated"}, true)
      assigns = %{form_changeset: changeset}

      result = Changeset.enrich(assigns, [])

      assert result.changeset_count == 1
      assert length(result.changesets) == 1

      [cs_info] = result.changesets
      assert cs_info.key == :form_changeset
      assert cs_info.valid? == true
      assert cs_info.error_count == 0
    end

    test "detects changeset with errors" do
      changeset = build_changeset(%{name: "test"}, %{name: ""}, false, name: ["can't be blank"])
      assigns = %{user_changeset: changeset}

      result = Changeset.enrich(assigns, [])

      assert result.changeset_count == 1
      [cs_info] = result.changesets
      assert cs_info.valid? == false
      assert cs_info.error_count == 1
      assert cs_info.error_fields == [:name]
    end

    test "detects multiple changesets" do
      cs1 = build_changeset(%{}, %{name: "a"}, true)
      cs2 = build_changeset(%{}, %{email: "b"}, false, email: ["invalid"])
      assigns = %{user_changeset: cs1, profile_changeset: cs2, other: "value"}

      result = Changeset.enrich(assigns, [])

      assert result.changeset_count == 2
      assert length(result.changesets) == 2
    end

    test "extracts changed fields" do
      # Only name changed, age stayed the same (so not in changes map)
      changeset = build_changeset(%{name: "old", age: 20}, %{name: "new"}, true)
      assigns = %{changeset: changeset}

      result = Changeset.enrich(assigns, [])

      [cs_info] = result.changesets
      assert :name in cs_info.changed_fields
      refute :age in cs_info.changed_fields
    end

    test "handles nested changesets in form struct" do
      changeset = build_changeset(%{name: "test"}, %{name: "updated"}, true)
      form = %Phoenix.HTML.Form{source: changeset}
      assigns = %{form: form}

      result = Changeset.enrich(assigns, [])

      assert result.changeset_count == 1
      [cs_info] = result.changesets
      assert cs_info.key == :form
    end
  end

  # Helper to build a mock changeset-like struct
  defp build_changeset(data, changes, valid?, errors \\ []) do
    %Ecto.Changeset{
      data: struct(MockSchema, data),
      changes: changes,
      valid?: valid?,
      errors: errors,
      action: if(valid?, do: nil, else: :insert)
    }
  end
end
