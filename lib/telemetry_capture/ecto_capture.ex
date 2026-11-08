defmodule Excessibility.TelemetryCapture.EctoCapture do
  @moduledoc """
  Ecto query capture for `Excessibility.TelemetryCapture`: accumulates each
  configured repo's query telemetry in the emitting process and, when
  `EXCESSIBILITY_QUERY_PLAN` asks for it, attaches an EXPLAIN plan summary.
  """

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.Enrichers.EctoQueries

  require Logger

  @downgrade_warned_key {__MODULE__, :analyze_downgrade_warned}

  @plan_warnings_key :excessibility_plan_warnings

  @in_explain_key :excessibility_in_explain

  @ecto_process_key :excessibility_ecto_queries

  @doc """
  The Ecto `[..., :query]` telemetry events for the configured `:ecto_repos`.
  """
  def ecto_query_events do
    Enum.map(TelemetryCapture.configured_repos(), &query_event/1)
  end

  @doc false
  # Public only so the plan-capture tests can drive it directly; not part of the
  # supported API. Records an Ecto query and, when plan capture is enabled and the
  # query is a SELECT, attaches value-free plan evidence via a crash-isolated,
  # re-entrancy-guarded EXPLAIN.
  def handle_ecto_query(_event, measurements, metadata, _config) do
    # Re-entrancy guard FIRST: while we run our own EXPLAIN, its `[:ecto, :query]`
    # telemetry fires in this same process. That event must NOT be recorded — it
    # is not a query the code under test ran, and recording it would both pollute
    # the timeline and (if it too were a SELECT) recurse. Return immediately.
    if Process.get(@in_explain_key) do
      :ok
    else
      # Read the plan-capture mode ONCE per query and thread it down the whole
      # attach path, so env/config is read a single time and any downgrade
      # warning fires at most once per query (not once per helper hop).
      record =
        measurements
        |> EctoQueries.build_query_record(metadata)
        |> maybe_attach_plan(metadata, TelemetryCapture.plan_capture_mode())

      Process.put(@ecto_process_key, [record | Process.get(@ecto_process_key, [])])
    end
  end

  @doc """
  Returns and clears any plan-capture warnings accumulated in the current
  process (oldest first), so a caller can surface them in the digest. Returns
  `[]` when none.
  """
  def drain_plan_warnings do
    warnings = @plan_warnings_key |> Process.get([]) |> Enum.reverse()
    Process.delete(@plan_warnings_key)
    warnings
  end

  @doc """
  Returns and clears the Ecto queries accumulated in the current process
  since the last flush, oldest first. Called at each captured event so
  queries are attributed to the event that ran them.
  """
  def flush_ecto_queries do
    queries = @ecto_process_key |> Process.get([]) |> Enum.reverse()
    Process.delete(@ecto_process_key)
    queries
  end

  @doc false
  # Test seam: clears the run-level downgrade-warning flag so a test can assert
  # the warn-once behavior deterministically.
  def reset_analyze_downgrade_warning, do: :persistent_term.erase(@downgrade_warned_key)

  @doc false
  # `plan_capture_mode/0` is evaluated once per query, and a journey spans many
  # LiveView processes, so a per-process flag floods the command with identical
  # downgrade warnings. The flag is global to the run's BEAM (the
  # `mix test` child that capture runs in), so the warning is emitted at most
  # once per command/run.
  def warn_analyze_downgrade_once do
    if :persistent_term.get(@downgrade_warned_key, false) == false do
      :persistent_term.put(@downgrade_warned_key, true)

      Logger.warning(
        "Excessibility: EXPLAIN ANALYZE requested but :query_plan_allow_analyze is not " <>
          "enabled; downgrading to EXPLAIN (no data-touching plan capture)."
      )
    end
  end

  # An Ecto repo emits queries at `telemetry_prefix ++ [:query]`. The prefix
  # defaults to the repo module's segments as atoms (MyApp.Repo -> [:my_app,
  # :repo]); a repo that overrides `:telemetry_prefix` is honored.
  defp query_event(repo) do
    prefix =
      case repo_telemetry_prefix(repo) do
        nil -> repo |> Module.split() |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
        prefix -> prefix
      end

    prefix ++ [:query]
  end

  defp repo_telemetry_prefix(repo) do
    if function_exported?(repo, :config, 0), do: repo.config()[:telemetry_prefix]
  rescue
    _ -> nil
  end

  # Attach a value-free `:plan` when plan capture is enabled. SELECTs get an
  # EXPLAIN run; non-SELECTs are never executed as EXPLAIN (privacy + safety) and
  # simply carry `plan: nil`. When plan capture is disabled we add no `:plan` key
  # at all, keeping the default record shape unchanged.
  defp maybe_attach_plan(record, metadata, mode) do
    if mode == :disabled do
      record
    else
      plan =
        if Excessibility.QueryEvidence.select?(record), do: capture_plan(record, metadata, mode)

      Map.put(record, :plan, plan)
    end
  end

  defp capture_plan(record, metadata, mode) do
    repo = Map.get(record, :repo)
    sql = Map.get(record, :query, "")
    # Params are read transiently for EXPLAIN only and are NEVER stored on the
    # record (privacy).
    params = Map.get(metadata, :params, [])

    if repo_queryable?(repo) do
      run_explain(repo, sql, params, mode)
    end
  end

  defp repo_queryable?(repo) do
    is_atom(repo) and not is_nil(repo) and Code.ensure_loaded?(repo) and
      (function_exported?(repo, :query, 3) or function_exported?(repo, :query, 2))
  end

  # Run EXPLAIN under the re-entrancy flag, tolerating any failure. The flag is
  # ALWAYS cleared in `after`, even if the repo call raises or exits, so a single
  # bad EXPLAIN can never wedge capture for the rest of the process.
  defp run_explain(repo, sql, params, mode) do
    Process.put(@in_explain_key, true)

    try do
      explain_sql = explain_sql_for(mode, sql)
      {:ok, result} = repo_query(repo, explain_sql, params)
      decoded = result.rows |> List.first() |> List.first()
      Excessibility.Dialect.resolve().parse_plan(decoded)
    rescue
      error ->
        add_plan_warning("EXPLAIN failed for #{inspect(repo)}: #{Exception.message(error)}")
        nil
    catch
      kind, reason ->
        add_plan_warning("EXPLAIN #{kind} for #{inspect(repo)}: #{inspect(reason)}")
        nil
    after
      Process.delete(@in_explain_key)
    end
  end

  defp repo_query(repo, sql, params) do
    if function_exported?(repo, :query, 3) do
      repo.query(sql, params, [])
    else
      repo.query(sql, params)
    end
  end

  # The dialect owns EXPLAIN syntax. For `:explain_analyze` we prefix the
  # ANALYZE variant, which is double-gated (env + :query_plan_allow_analyze) and
  # only ever reached for SELECTs. NOTE: EXPLAIN ANALYZE *executes* the statement,
  # so it should only be run inside a DB sandbox; a dialect-level ANALYZE builder
  # can replace this local helper later.
  defp explain_sql_for(:explain_analyze, sql), do: analyze_explain_sql(sql)
  defp explain_sql_for(_mode, sql), do: Excessibility.Dialect.resolve().explain_sql(sql)

  # SELECT-only + sandbox caveat: see `explain_sql_for/2`. Postgres-shaped.
  defp analyze_explain_sql(sql), do: "EXPLAIN (ANALYZE, FORMAT JSON) " <> sql

  defp add_plan_warning(message) do
    Process.put(@plan_warnings_key, [message | Process.get(@plan_warnings_key, [])])
  end
end
