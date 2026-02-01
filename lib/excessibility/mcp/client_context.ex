defmodule Excessibility.MCP.ClientContext do
  @moduledoc """
  Helpers for getting the MCP client's context (working directory, etc).

  The MCP server runs from the excessibility project directory, but tools often
  need to operate in the client's project directory. This module provides helpers
  to determine the correct working directory.

  The client's working directory is determined in this order:
  1. `MCP_CLIENT_CWD` environment variable (set by the mcp-server wrapper script)
  2. Explicit `cwd` parameter passed to the tool (for backward compatibility)
  3. Current working directory (fallback)
  """

  @doc """
  Gets the client's working directory.

  ## Options
    * `:cwd` - Explicit working directory override (for backward compatibility)

  ## Examples

      iex> ClientContext.get_cwd()
      "/home/user/projects/my_app"

      iex> ClientContext.get_cwd(cwd: "/custom/path")
      "/custom/path"
  """
  def get_cwd(opts \\ []) do
    explicit_cwd = Keyword.get(opts, :cwd)

    cond do
      # Explicit cwd parameter takes precedence (backward compat)
      explicit_cwd && File.dir?(explicit_cwd) ->
        explicit_cwd

      # Check MCP_CLIENT_CWD environment variable
      env_cwd = System.get_env("MCP_CLIENT_CWD") ->
        if File.dir?(env_cwd), do: env_cwd, else: File.cwd!()

      # Fallback to current directory
      true ->
        File.cwd!()
    end
  end

  @doc """
  Builds a path relative to the client's working directory.

  ## Examples

      iex> ClientContext.client_path("test/excessibility/timeline.json")
      "/home/user/projects/my_app/test/excessibility/timeline.json"
  """
  def client_path(relative_path, opts \\ []) do
    Path.join(get_cwd(opts), relative_path)
  end

  @doc """
  Returns command options for System.cmd with the correct working directory.

  ## Examples

      iex> ClientContext.cmd_opts()
      [cd: "/home/user/projects/my_app"]

      iex> ClientContext.cmd_opts(stderr_to_stdout: true)
      [cd: "/home/user/projects/my_app", stderr_to_stdout: true]
  """
  def cmd_opts(extra_opts \\ []) do
    cwd = get_cwd(extra_opts)
    extra_opts = Keyword.delete(extra_opts, :cwd)
    [{:cd, cwd} | extra_opts]
  end
end
