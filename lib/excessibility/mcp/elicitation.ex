defmodule Excessibility.MCP.Elicitation do
  @moduledoc """
  Handles the MCP elicitation protocol for structured user interaction.

  Elicitation allows MCP tools to pause execution and ask the user a structured
  question. The server sends an `elicitation/create` request to the client, which
  presents the question and returns the user's response.

  ## Usage in Tools

  Tools receive an `elicit` callback via their opts when the server supports
  elicitation:

      def execute(args, opts) do
        case opts[:elicit] do
          nil ->
            # No elicitation support, proceed with defaults
            do_work(args)

          elicit ->
            schema = %{
              "type" => "object",
              "properties" => %{
                "approved" => %{"type" => "boolean", "description" => "Approve this action?"}
              }
            }

            case elicit.("Found 5 issues. Fix them?", schema) do
              {:accept, %{"approved" => true}} -> fix_issues(args)
              {:accept, _} -> {:ok, %{"status" => "skipped"}}
              :decline -> {:ok, %{"status" => "declined"}}
              :cancel -> {:error, "cancelled by user"}
            end
        end
      end

  ## Protocol

  The elicitation flow follows JSON-RPC 2.0:

  1. Server sends `elicitation/create` request with message and schema
  2. Client responds with `{action: "accept"|"decline"|"cancel", content: {...}}`
  """

  @doc """
  Builds a JSON-RPC 2.0 elicitation request.

  Returns a map with method `"elicitation/create"` and params containing
  the message and requested schema.
  """
  @spec build_request(integer(), String.t(), map()) :: map()
  def build_request(id, message, requested_schema) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "elicitation/create",
      "params" => %{
        "message" => message,
        "requestedSchema" => requested_schema
      }
    }
  end

  @doc """
  Parses a JSON-RPC elicitation response.

  Returns:
  - `{:accept, content}` when the user accepted and provided content
  - `:decline` when the user declined
  - `:cancel` when the user cancelled
  """
  @spec parse_response(map()) :: {:accept, map()} | :decline | :cancel | {:error, term()}
  def parse_response(%{"result" => %{"action" => "accept", "content" => content}}) do
    {:accept, content}
  end

  def parse_response(%{"result" => %{"action" => "decline"}}) do
    :decline
  end

  def parse_response(%{"result" => %{"action" => "cancel"}}) do
    :cancel
  end

  def parse_response(_other), do: {:error, :invalid_response}

  @doc """
  Builds an elicitation callback function for use in tool opts.

  Returns `nil` if either `write_fn` or `read_fn` is nil (elicitation not supported).
  Otherwise returns a 2-arity function `fn message, schema -> result` that handles
  the full elicitation round-trip: building the request, writing it as JSON,
  reading the response, and parsing it.

  ## Parameters

  - `write_fn` - A 1-arity function that writes a string to the client
  - `read_fn` - A 0-arity function that reads a string response from the client
  """
  @spec build_callback((String.t() -> :ok) | nil, (-> String.t()) | nil) ::
          (String.t(), map() -> {:accept, map()} | :decline | :cancel | {:error, term()}) | nil
  def build_callback(nil, _read_fn), do: nil
  def build_callback(_write_fn, nil), do: nil

  def build_callback(write_fn, read_fn) do
    fn message, schema ->
      id = System.unique_integer([:positive])
      request = build_request(id, message, schema)
      json = Jason.encode!(request) <> "\n"

      write_fn.(json)

      case Jason.decode(read_fn.()) do
        {:ok, decoded} -> parse_response(decoded)
        {:error, _} -> {:error, :invalid_json}
      end
    end
  end
end
