defmodule Excessibility.MCP.Subprocess do
  @moduledoc """
  Subprocess execution with proper timeout handling.

  Unlike `System.cmd/3` wrapped in `Task.yield/shutdown`, this module
  actually kills the underlying OS process when a timeout occurs.
  """

  require Logger

  # Simple file-based debug logging (works even when Logger is disabled)
  # Set MCP_LOG_FILE=/tmp/mcp.log to enable
  defp debug_log(msg) do
    Logger.debug(msg)

    case System.get_env("MCP_LOG_FILE") do
      nil -> :ok
      path -> File.write!(path, "[#{DateTime.utc_now()}] #{msg}\n", [:append])
    end
  end

  @doc """
  Runs a command with optional timeout.

  ## Options

    * `:timeout` - Timeout in milliseconds. If nil, no timeout is applied.
    * `:cd` - Working directory for the command.
    * `:env` - Environment variables as a list of `{key, value}` tuples.
    * `:stderr_to_stdout` - If true, redirects stderr to stdout (default: false).

  ## Returns

    * `{output, exit_code}` on success or timeout
    * On timeout, returns `{"Error: Command timed out after N seconds", 124}`

  ## Examples

      iex> Subprocess.run("echo", ["hello"], timeout: 5000)
      {"hello\\n", 0}

      iex> Subprocess.run("sleep", ["10"], timeout: 100)
      {"Error: Command timed out after 0 seconds", 124}
  """
  def run(cmd, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    cd = Keyword.get(opts, :cd)
    env = Keyword.get(opts, :env, [])
    stderr_to_stdout? = Keyword.get(opts, :stderr_to_stdout, false)

    debug_log("Subprocess.run: cmd=#{cmd} args=#{inspect(args)} cd=#{inspect(cd)} timeout=#{inspect(timeout)}")

    port_opts = build_port_opts(cmd, args, cd, env, stderr_to_stdout?)

    result =
      if timeout do
        run_with_timeout(port_opts, timeout)
      else
        run_without_timeout(port_opts)
      end

    {output, exit_code} = result
    debug_log("Subprocess.run completed: exit_code=#{exit_code} output_length=#{String.length(output)}")
    result
  end

  defp build_port_opts(cmd, args, cd, env, stderr_to_stdout?) do
    opts = [
      :binary,
      :exit_status,
      :use_stdio,
      args: args
    ]

    opts = if cd, do: [{:cd, to_charlist(cd)} | opts], else: opts
    opts = if env != [], do: [{:env, format_env(env)} | opts], else: opts
    opts = if stderr_to_stdout?, do: [:stderr_to_stdout | opts], else: opts

    {:spawn_executable, find_executable(cmd), opts}
  end

  defp find_executable(cmd) do
    case System.find_executable(cmd) do
      nil -> raise "Executable not found: #{cmd}"
      path -> to_charlist(path)
    end
  end

  defp format_env(env) do
    Enum.map(env, fn {k, v} -> {to_charlist(to_string(k)), to_charlist(to_string(v))} end)
  end

  defp run_without_timeout({:spawn_executable, executable, opts}) do
    port = Port.open({:spawn_executable, executable}, opts)
    collect_output(port, [])
  end

  defp run_with_timeout({:spawn_executable, executable, opts}, timeout) do
    parent = self()
    ref = make_ref()

    # Spawn a process to run the port and track the OS PID
    {pid, monitor_ref} =
      spawn_monitor(fn ->
        port = Port.open({:spawn_executable, executable}, opts)
        # Get the OS PID immediately
        os_pid = get_os_pid(port)
        send(parent, {ref, :started, os_pid})
        result = collect_output(port, [])
        send(parent, {ref, :done, result})
      end)

    # Wait for the process to start and get the OS PID
    os_pid =
      receive do
        {^ref, :started, os_pid} -> os_pid
      after
        1000 -> nil
      end

    receive do
      {^ref, :done, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        if os_pid, do: kill_os_process(os_pid)
        {"Error: Process crashed: #{inspect(reason)}", 1}
    after
      timeout ->
        # Kill the OS process first (this is what actually stops the command)
        if os_pid, do: kill_os_process(os_pid)

        # Then kill the Elixir process
        Process.exit(pid, :kill)
        Process.demonitor(monitor_ref, [:flush])

        # Flush any remaining messages
        flush_messages(ref)

        {"Error: Command timed out after #{div(timeout, 1000)} seconds", 124}
    end
  end

  defp get_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> os_pid
      _ -> nil
    end
  end

  defp kill_os_process(os_pid) when is_integer(os_pid) do
    # Kill the entire process tree recursively
    kill_process_tree(os_pid)
  rescue
    _ -> :ok
  end

  defp kill_os_process(_), do: :ok

  defp kill_process_tree(pid) do
    pid_str = to_string(pid)

    # First, recursively kill all children
    {children_output, _} = System.cmd("pgrep", ["-P", pid_str], stderr_to_stdout: true)

    children_output
    |> String.split("\n", trim: true)
    |> Enum.each(fn child_pid_str ->
      case Integer.parse(child_pid_str) do
        {child_pid, _} -> kill_process_tree(child_pid)
        :error -> :ok
      end
    end)

    # Then kill the process itself
    System.cmd("kill", ["-9", pid_str], stderr_to_stdout: true)
  rescue
    _ -> :ok
  end

  defp collect_output(port, acc, chunks \\ 0) do
    receive do
      {^port, {:data, data}} ->
        if rem(chunks, 100) == 0 do
          debug_log("Subprocess: received chunk #{chunks}, total bytes so far: #{IO.iodata_length(acc)}")
        end

        collect_output(port, [data | acc], chunks + 1)

      {^port, {:exit_status, status}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        debug_log("Subprocess: exit_status=#{status}, total chunks=#{chunks}, output_bytes=#{byte_size(output)}")
        {output, status}
    after
      60_000 ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        debug_log("WARNING: Subprocess: no data for 60s, chunks=#{chunks}, bytes=#{byte_size(output)}")
        collect_output(port, acc, chunks)
    end
  end

  defp flush_messages(ref) do
    receive do
      {^ref, _} -> flush_messages(ref)
    after
      0 -> :ok
    end
  end
end
