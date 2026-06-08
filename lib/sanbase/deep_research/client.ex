defmodule Sanbase.DeepResearch.Client do
  @moduledoc """
  HTTP/SSE client for the LangGraph deep research agent. The LiveView connects
  directly to the LangGraph server (`Sanbase.DeepResearch.Config.base_url/0`),
  no auth header (trusted internal dev service) — no separate proxy tier.

  `stream_run/3` is meant to run via the LiveView's `start_async/3`. During the
  stream it forwards each parsed event to the LiveView pid as a
  `{:dra_event, result}` message (`result` is an `EventParser.parse/1` map), and
  returns the terminal status (`:ok` / `{:error, reason}`) for `handle_async/3`.

  Thread creation, cancellation and the state-poll fallback are plain request/
  response calls.
  """

  alias Sanbase.DeepResearch.{Config, EventParser}

  require Logger

  # Generous gap between SSE chunks — a research run can pause for a while while
  # the model thinks before emitting the next event.
  @stream_receive_timeout 300_000
  @request_timeout 30_000

  @doc "Create a new thread. Returns `{:ok, thread_id}` or `{:error, reason}`."
  @spec create_thread() :: {:ok, String.t()} | {:error, String.t()}
  def create_thread() do
    case Req.post(url("/threads"), json: %{}, receive_timeout: @request_timeout, retry: false) do
      {:ok, %{status: status, body: %{"thread_id" => thread_id}}} when status in 200..299 ->
        {:ok, thread_id}

      {:ok, %{status: status, body: body}} ->
        {:error, "create_thread failed (HTTP #{status}): #{inspect(body)}"}

      {:error, error} ->
        {:error, error_message(error)}
    end
  end

  @doc "Cancel an in-flight run. Best-effort; errors are swallowed."
  @spec cancel_run(String.t(), String.t()) :: :ok
  def cancel_run(thread_id, run_id) do
    Req.post(url("/threads/#{thread_id}/runs/#{run_id}/cancel"),
      json: %{},
      receive_timeout: @request_timeout,
      retry: false
    )

    :ok
  rescue
    error ->
      Logger.warning("DeepResearch cancel_run failed: #{Exception.message(error)}")
      :ok
  end

  @doc "Fetch the thread state (poll fallback after the stream closes)."
  @spec get_state(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_state(thread_id) do
    case Req.get(url("/threads/#{thread_id}/state"),
           receive_timeout: @request_timeout,
           retry: false
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "get_state failed (HTTP #{status})"}
      {:error, error} -> {:error, error_message(error)}
    end
  end

  @doc """
  Stream a run on `thread_id`, forwarding parsed events to `lv_pid` as
  `{:dra_event, result}` messages during the stream. Blocks the calling process
  until the stream ends — run it via `start_async/3` so the LiveView keeps
  serving heartbeats. Returns the terminal status for `handle_async/3`.
  """
  @spec stream_run(String.t(), String.t(), pid(), [map()]) :: :ok | {:error, String.t()}
  def stream_run(thread_id, message, lv_pid, mcp_servers \\ []) do
    Process.put(:dra_buffer, "")
    payload = Config.run_payload(message, mcp_servers: mcp_servers)

    result =
      Req.post(url("/threads/#{thread_id}/runs/stream"),
        json: payload,
        receive_timeout: @stream_receive_timeout,
        retry: false,
        into: fn {:data, data}, {req, resp} ->
          handle_chunk(data, lv_pid)
          {:cont, {req, resp}}
        end
      )

    case result do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, "Research stream failed (HTTP #{status})"}
      {:error, error} -> {:error, error_message(error)}
    end
  end

  # Accumulate the partial-line buffer (in this Task's process dictionary) and
  # dispatch every complete `data:` line, buffering partial lines across chunks.
  defp handle_chunk(data, lv_pid) do
    buffer = Process.get(:dra_buffer, "") <> data
    parts = String.split(buffer, "\n")
    {complete, [rest]} = Enum.split(parts, -1)
    Process.put(:dra_buffer, rest)
    Enum.each(complete, &handle_line(&1, lv_pid))
  end

  defp handle_line("data:" <> rest, lv_pid) do
    raw = String.trim(rest)

    if raw != "" and raw != "[DONE]" do
      with {:ok, value} <- Jason.decode(raw),
           result when map_size(result) > 0 <- EventParser.parse(value) do
        send(lv_pid, {:dra_event, result})
      else
        _ -> :ok
      end
    end
  end

  # Non-data lines: `event:` mode markers, comments, blank separators — ignored.
  defp handle_line(_line, _lv_pid), do: :ok

  defp url(path), do: Config.base_url() <> path

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)
end
