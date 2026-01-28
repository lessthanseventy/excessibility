defmodule Excessibility.TelemetryCapture.Enrichers.Changeset do
  @moduledoc """
  Enriches timeline events with Ecto changeset information.

  Detects Ecto.Changeset structs in assigns and extracts:
  - Validity status
  - Error count and fields with errors
  - Changed fields

  Also detects changesets nested in Phoenix.HTML.Form structs.

  ## Output

  Adds to each timeline event:
  - `changeset_count` - Number of changesets found
  - `changesets` - List of changeset info maps with:
    - `key` - The assign key
    - `valid?` - Whether changeset is valid
    - `error_count` - Number of errors
    - `error_fields` - List of fields with errors
    - `changed_fields` - List of fields that were changed
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  @impl true
  def name, do: :changeset

  @impl true
  def enrich(assigns, _opts) do
    changesets = find_changesets(assigns)

    %{
      changeset_count: length(changesets),
      changesets: changesets
    }
  end

  defp find_changesets(assigns) do
    assigns
    |> Enum.flat_map(fn {key, value} ->
      case extract_changeset(value) do
        nil -> []
        changeset -> [build_changeset_info(key, changeset)]
      end
    end)
    |> Enum.sort_by(& &1.key)
  end

  # Check struct type dynamically to avoid compile-time dependency on Ecto
  defp extract_changeset(%{__struct__: Ecto.Changeset} = changeset), do: changeset

  defp extract_changeset(%{__struct__: Phoenix.HTML.Form, source: %{__struct__: Ecto.Changeset} = changeset}),
    do: changeset

  defp extract_changeset(_), do: nil

  defp build_changeset_info(key, changeset) do
    %{
      key: key,
      valid?: changeset.valid?,
      error_count: length(changeset.errors),
      error_fields: Enum.map(changeset.errors, fn {field, _} -> field end),
      changed_fields: Map.keys(changeset.changes)
    }
  end
end
