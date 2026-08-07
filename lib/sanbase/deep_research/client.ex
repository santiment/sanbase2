defmodule Sanbase.DeepResearch.Client do
  @moduledoc """
  HTTP/SSE client for the LangGraph deep research agent. The LiveView connects
  directly to the LangGraph server (`Sanbase.DeepResearch.Config.base_url/0`) —
  no separate proxy tier. When `Config.auth_token/0` is set, every request
  carries it as an `Authorization: Bearer` header; unset means no auth header
  (the trusted local dev server).

  `stream_run/4` is meant to run via the LiveView's `start_async/3`. During the
  stream it forwards each parsed event to the LiveView pid as a
  `{:dra_event, ref, result}` message (`result` is an `EventParser.parse/1` map),
  and returns the terminal status (`:ok` / `{:error, reason}`) for
  `handle_async/3`. `ref` is an opaque correlation token supplied by the caller
  and echoed back untouched, so a caller with several runs in its lifetime can
  discard events belonging to a superseded one.

  Thread creation, cancellation and the state-poll fallback are plain request/
  response calls.
  """

  alias Sanbase.DeepResearch.{Config, EventParser, SSE}

  require Logger

  # Generous gap between SSE chunks — a research run can pause for a while while
  # the model thinks before emitting the next event.
  @stream_receive_timeout 300_000
  @request_timeout 30_000

  @buffer_key :dra_sse_buffer

  @doc "Create a new thread. Returns `{:ok, thread_id}` or `{:error, reason}`."
  @spec create_thread() :: {:ok, String.t()} | {:error, String.t()}
  def create_thread() do
    case Req.post(
           url("/threads"),
           request_opts(json: %{}, receive_timeout: @request_timeout, retry: false)
         ) do
      {:ok, %{status: status, body: %{"thread_id" => thread_id}}} when status in 200..299 ->
        {:ok, thread_id}

      {:ok, %{status: status, body: body}} ->
        {:error, "create_thread failed (HTTP #{status}): #{inspect(body)}"}

      {:error, error} ->
        {:error, error_message(error)}
    end
  end

  @doc """
  Cancel an in-flight run. Best-effort (always returns `:ok`), but every failure
  is logged instead of swallowed silently — the thread is reused for later turns,
  so a failed cancel leaving the previous run alive is worth a warning.
  """
  @spec cancel_run(String.t(), String.t()) :: :ok
  def cancel_run(thread_id, run_id) do
    case Req.post(
           url("/threads/#{thread_id}/runs/#{run_id}/cancel"),
           request_opts(json: %{}, receive_timeout: @request_timeout, retry: false)
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("DeepResearch cancel_run failed (HTTP #{status}): #{inspect(body)}")
        :ok

      {:error, error} ->
        Logger.warning("DeepResearch cancel_run failed: #{error_message(error)}")
        :ok
    end
  rescue
    error ->
      Logger.warning("DeepResearch cancel_run failed: #{Exception.message(error)}")
      :ok
  end

  @doc """
  Cancel every in-flight run on `thread_id`. Covers the early-cancel window: the
  user hits Stop before the stream has delivered a `run_id`, but the server-side
  run already exists — so look up the thread's active runs and cancel each.
  Best-effort, like `cancel_run/2`.
  """
  @spec cancel_active_runs(String.t()) :: :ok
  def cancel_active_runs(thread_id) do
    case Req.get(
           url("/threads/#{thread_id}/runs"),
           request_opts(receive_timeout: @request_timeout, retry: false)
         ) do
      {:ok, %{status: status, body: runs}} when status in 200..299 and is_list(runs) ->
        runs
        |> Enum.filter(&(&1["status"] in ["pending", "running"]))
        |> Enum.each(&cancel_run(thread_id, &1["run_id"]))

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "DeepResearch cancel_active_runs failed (HTTP #{status}): #{inspect(body)}"
        )

        :ok

      {:error, error} ->
        Logger.warning("DeepResearch cancel_active_runs failed: #{error_message(error)}")
        :ok
    end
  rescue
    error ->
      Logger.warning("DeepResearch cancel_active_runs failed: #{Exception.message(error)}")
      :ok
  end

  @doc "Fetch the thread state (poll fallback after the stream closes)."
  @spec get_state(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_state(thread_id) do
    case Req.get(
           url("/threads/#{thread_id}/state"),
           request_opts(receive_timeout: @request_timeout, retry: false)
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "get_state failed (HTTP #{status})"}
      {:error, error} -> {:error, error_message(error)}
    end
  end

  @doc """
  Stream a run on `thread_id`, forwarding parsed events to `lv_pid` as
  `{:dra_event, ref, result}` messages during the stream. Blocks the calling
  process until the stream ends — run it via `start_async/3` so the LiveView keeps
  serving heartbeats. Returns the terminal status for `handle_async/3`.

  `opts[:ref]` is echoed back in every event message (see the moduledoc); the
  rest are forwarded to `Config.run_payload/2`: `:mcp_servers` (list of agent MCP
  server maps) and `:model_tier` (the price-tier name picked in the UI).
  """
  @spec stream_run(String.t(), String.t(), pid(), keyword()) :: :ok | {:error, String.t()}
  def stream_run(thread_id, message, lv_pid, opts \\ []) do
    warn_if_insecure_base_url()
    {ref, opts} = Keyword.pop(opts, :ref)
    payload = Config.run_payload(message, opts)

    result =
      Req.post(
        url("/threads/#{thread_id}/runs/stream"),
        request_opts(
          json: payload,
          receive_timeout: @stream_receive_timeout,
          retry: false,
          # The partial-line buffer rides along on the response's private map, so
          # the framing state is explicit and scoped to this request rather than
          # hidden in the calling process's dictionary.
          into: fn {:data, data}, {req, resp} ->
            {lines, buffer} = SSE.feed(Req.Response.get_private(resp, @buffer_key, ""), data)
            Enum.each(lines, &handle_line(&1, lv_pid, ref))
            {:cont, {req, Req.Response.put_private(resp, @buffer_key, buffer)}}
          end
        )
      )

    # The last SSE event may arrive without a trailing newline, leaving it in the
    # buffer — flush it so a terminal `run_id`/`error`/`report` isn't dropped.
    flush_buffer(result, lv_pid, ref)

    case result do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, "Research stream failed (HTTP #{status})"}
      {:error, error} -> {:error, error_message(error)}
    end
  end

  defp flush_buffer({:ok, %Req.Response{} = resp}, lv_pid, ref) do
    {lines, ""} = resp |> Req.Response.get_private(@buffer_key, "") |> SSE.flush()
    Enum.each(lines, &handle_line(&1, lv_pid, ref))
  end

  # A transport-level failure has no response to drain.
  defp flush_buffer(_result, _lv_pid, _ref), do: :ok

  defp handle_line("data:" <> rest, lv_pid, ref) do
    raw = String.trim(rest)

    if raw != "" and raw != "[DONE]" do
      with {:ok, value} <- Jason.decode(raw),
           result when map_size(result) > 0 <- EventParser.parse(value) do
        send(lv_pid, {:dra_event, ref, result})
      else
        _ -> :ok
      end
    end
  end

  # Non-data lines: `event:` mode markers, comments, blank separators — ignored.
  defp handle_line(_line, _lv_pid, _ref), do: :ok

  defp url(path), do: Config.base_url() <> path

  # Attach the deploy's bearer token (if configured) to a request's options.
  defp request_opts(opts) do
    case Config.auth_token() do
      nil -> opts
      token -> Keyword.put(opts, :auth, {:bearer, token})
    end
  end

  # The run payload carries the OpenRouter/Tavily API keys, so a non-local plain
  # HTTP base URL puts them on the wire in cleartext. Warn once per run rather
  # than refuse — the default is localhost and a remote deploy should be https.
  defp warn_if_insecure_base_url() do
    case URI.parse(Config.base_url()) do
      %URI{scheme: "http", host: host} when host not in ["localhost", "127.0.0.1", "::1"] ->
        Logger.warning(
          "DeepResearch base_url is plain HTTP to a non-local host (#{host}) — the run " <>
            "payload's API keys are sent in cleartext. Use https for remote agents."
        )

      _ ->
        :ok
    end
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)
end
