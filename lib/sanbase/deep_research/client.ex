defmodule Sanbase.DeepResearch.Client do
  @moduledoc """
  HTTP/SSE client for the LangGraph deep research agent (`Config.base_url/0`, no
  proxy tier). `Config.auth_token/0`, when set, rides along as a bearer header.

  `stream_run/4` forwards parsed events to `lv_pid` as `{:dra_event, ref, result}`
  and returns the terminal status for `handle_async/3`. `ref` is the caller's
  correlation token, echoed untouched so events of a superseded run can be dropped.
  Everything else is plain request/response.

  Every call fails with `{:error, %Sanbase.DeepResearch.Failure{}}` and logs it —
  the turn's copy closes with the tab, and a run that broke unwatched must still be
  findable.

  ## Timeouts

  Nothing here caps a run's duration: Finch's `:request_timeout` stays `:infinity`.
  Bounded instead:

    * **Connect** (5s, every call) — an unreachable host fails fast rather than
      surfacing later as an unexplained `"timeout"`.
    * **Stream silence** (15 min) — `:receive_timeout` is per chunk, so this is the
      longest a run may send NOTHING, not the longest it may run. Exists only
      because a half-open socket never announces itself; hitting it parks the turn
      `:paused` and Continue resumes the same thread.
    * **One-shot calls** (15s per attempt, one retry) — thread create, cancel, state
      poll, answered from the agent's own store, so slower means a sick server.

  A reverse proxy has idle timeouts we cannot see from here: a run cut at a round
  number of seconds is the proxy, not this module.
  """

  alias Sanbase.DeepResearch.{Config, Event, EventParser, Failure, SSE}

  require Logger

  # See the moduledoc's "Timeouts" section for why each of these exists.

  # Per chunk, not per run: Finch restarts the clock on every byte (`Mint.HTTP.recv/3`).
  # Not `:infinity`, or a half-open socket hangs the run forever.
  @stream_idle_timeout 900_000

  @connect_timeout 5_000
  @request_timeout 15_000
  @request_retries 1

  # Fixed rather than Req's exponential default, so the worst case below is
  # arithmetic instead of a guess.
  @retry_delay 500

  # Worst cost of ONE one-shot call: connect + read per attempt, plus the backoff between.
  # A caller wrapping one in its own task must outlast this. Bounds no run.
  @oneshot_worst_case (@request_retries + 1) * (@connect_timeout + @request_timeout) +
                        @request_retries * @retry_delay + 1_000

  @buffer_key :dra_sse_buffer

  @doc "Create a new thread. Returns `{:ok, thread_id}` or `{:error, failure}`."
  @spec create_thread() :: {:ok, String.t()} | {:error, Failure.t()}
  def create_thread() do
    case Req.post(url("/threads"), oneshot_opts(json: %{})) do
      {:ok, %{status: status, body: %{"thread_id" => thread_id}}} when status in 200..299 ->
        {:ok, thread_id}

      {:ok, %{status: status, body: body}} ->
        {:error, response_failure("create_thread", status, body)}

      {:error, error} ->
        {:error, connection_failure("create_thread", error)}
    end
  end

  @doc """
  Cancel an in-flight run. Reports failure because the thread is reused for later
  turns, so a cancel that left the previous run alive is worth surfacing.
  """
  @spec cancel_run(String.t(), String.t()) :: :ok | {:error, Failure.t()}
  def cancel_run(thread_id, run_id) do
    case Req.post(url("/threads/#{thread_id}/runs/#{run_id}/cancel"), oneshot_opts(json: %{})) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, response_failure("cancel_run", status, body)}

      {:error, error} ->
        {:error, connection_failure("cancel_run", error)}
    end
  rescue
    error -> {:error, log(Failure.crashed(error))}
  end

  @doc """
  Cancel every in-flight run on `thread_id`. Two callers: the early-cancel window (Stop
  pressed before the stream reported a `run_id`, though the run already exists), and
  `Runner` before it starts a turn, since anything active on the thread by then is a
  leftover — e.g. a run the agent server resumed from disk after a restart — that would
  only queue the new run behind it. Best-effort — `cancel_run/2` logs the individual
  failures.
  """
  @spec cancel_active_runs(String.t()) :: :ok
  def cancel_active_runs(thread_id) do
    case Req.get(url("/threads/#{thread_id}/runs"), oneshot_opts([])) do
      {:ok, %{status: status, body: runs}} when status in 200..299 and is_list(runs) ->
        # Concurrent: sequential cancels stack their HTTP timeouts.
        runs
        |> Enum.filter(&(&1["status"] in ["pending", "running"]))
        |> Task.async_stream(&cancel_run(thread_id, &1["run_id"]),
          max_concurrency: 5,
          ordered: false,
          timeout: @oneshot_worst_case,
          on_timeout: :kill_task
        )
        |> Stream.run()

      {:ok, %{status: status, body: body}} ->
        response_failure("cancel_active_runs", status, body)
        :ok

      {:error, error} ->
        connection_failure("cancel_active_runs", error)
        :ok
    end
  rescue
    error ->
      log(Failure.crashed(error))
      :ok
  end

  @doc "Fetch the thread state (poll fallback after the stream closes)."
  @spec get_state(String.t()) :: {:ok, map()} | {:error, Failure.t()}
  def get_state(thread_id) do
    case Req.get(url("/threads/#{thread_id}/state"), oneshot_opts([])) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, response_failure("get_state", status, body)}

      {:error, error} ->
        {:error, connection_failure("get_state", error)}
    end
  end

  @doc """
  The run's record — its `"status"` (`pending` / `running` / `success` / `error` /
  `timeout` / `interrupted`) is what the silence watchdog needs.
  """
  @spec get_run(String.t(), String.t()) :: {:ok, map()} | {:error, Failure.t()}
  def get_run(thread_id, run_id) do
    case Req.get(url("/threads/#{thread_id}/runs/#{run_id}"), oneshot_opts([])) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, response_failure("get_run", status, body)}

      {:error, error} ->
        {:error, connection_failure("get_run", error)}
    end
  end

  @doc """
  Stream a run on `thread_id`, forwarding events to `lv_pid` as
  `{:dra_event, ref, result}`. Blocks for as long as the run takes — hours if the
  research takes hours; only its silence is bounded (see "Timeouts"). Run it under
  `start_async/3`.

  `opts[:ref]` is echoed back in every event message (see the moduledoc); the
  rest are forwarded to `Config.run_payload/2`: `:mcp_servers` (list of agent MCP
  server maps) and `:model_tier` (the price-tier name picked in the UI).
  """
  @spec stream_run(String.t(), String.t(), pid(), keyword()) :: :ok | {:error, Failure.t()}
  def stream_run(thread_id, message, lv_pid, opts \\ []) do
    with :ok <- check_base_url_security() do
      do_stream_run(thread_id, message, lv_pid, opts)
    end
  end

  defp do_stream_run(thread_id, message, lv_pid, opts) do
    {ref, opts} = Keyword.pop(opts, :ref)
    payload = Config.run_payload(message, opts)

    result =
      Req.post(
        url("/threads/#{thread_id}/runs/stream"),
        request_opts(
          json: payload,
          receive_timeout: @stream_idle_timeout,
          # A retry would start a SECOND run, interleaving its events with the first's.
          retry: false,
          # Framing state on the response's private map, scoped to this request.
          into: fn {:data, data}, {req, resp} ->
            {lines, buffer} = SSE.feed(Req.Response.get_private(resp, @buffer_key, ""), data)
            Enum.each(lines, &handle_line(&1, lv_pid, ref))
            {:cont, {req, Req.Response.put_private(resp, @buffer_key, buffer)}}
          end
        )
      )

    # A last event without a trailing newline stays in the buffer - flush it, or a terminal
    # `run_id`/`error`/`report` is lost.
    flush_buffer(result, lv_pid, ref)

    case result do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, response_failure("The run", status, body)}
      {:error, error} -> {:error, connection_failure("the research stream", error)}
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
           event <- EventParser.parse(value),
           false <- Event.empty?(event) do
        send(lv_pid, {:dra_event, ref, event})
      else
        _ -> :ok
      end
    end
  end

  # Non-data lines: `event:` mode markers, comments, blank separators — ignored.
  defp handle_line(_line, _lv_pid, _ref), do: :ok

  defp url(path), do: Config.base_url() <> path

  # `:transient`, not `:safe_transient`, so the POSTs retry too: a retried create leaves
  # one unused thread, a repeated cancel is idempotent.
  defp oneshot_opts(opts) do
    opts
    |> Keyword.merge(
      receive_timeout: @request_timeout,
      retry: :transient,
      max_retries: @request_retries,
      retry_delay: @retry_delay
    )
    |> request_opts()
  end

  defp request_opts(opts) do
    opts = Keyword.put(opts, :connect_options, timeout: @connect_timeout)

    case Config.auth_token() do
      nil -> opts
      token -> Keyword.put(opts, :auth, {:bearer, token})
    end
  end

  # The run payload carries the OpenRouter/Tavily keys, so plain HTTP to a non-local host
  # sends them in cleartext. Deployed fails closed, except *.cluster.local; dev only warns,
  # since a remote agent may be on a trusted network.
  defp check_base_url_security() do
    case URI.parse(Config.base_url()) do
      %URI{scheme: "http", host: host} when host not in ["localhost", "127.0.0.1", "::1"] ->
        message =
          "DeepResearch base_url is plain HTTP to a non-local host (#{host}) — the run " <>
            "payload's API keys are sent in cleartext. Use https for remote agents."

        if deployed_env?() and not cluster_internal_host?(host) do
          Logger.error(message)
          {:error, Failure.refused(message)}
        else
          Logger.warning(message)
          :ok
        end

      _ ->
        :ok
    end
  end

  defp cluster_internal_host?(host) do
    String.ends_with?(host, ".svc.cluster.local") or String.ends_with?(host, ".cluster.local")
  end

  defp deployed_env?() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) in ["stage", "prod"]
  end

  defp connection_failure(operation, error),
    do: log(Failure.connection(operation, Config.base_url(), error))

  defp response_failure(operation, status, body),
    do: log(Failure.response(operation, status, body))

  defp log(%Failure{} = failure) do
    Logger.warning("DeepResearch: #{failure.message}")
    failure
  end
end
