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

  Every call fails with `{:error, %Sanbase.DeepResearch.Failure{}}` — a message
  naming the call, the agent and the reason, plus whether the turn is worth
  resuming. Failures are logged here too: the turn's copy can be closed with the
  tab, and a run that broke with nobody watching still has to be findable.

  ## Timeouts

  **Nothing here caps how long a run may take.** A research run that thinks, calls
  tools and loops for twenty minutes or two hours is expected, and no timeout in
  this module counts against it. The stream has no total-duration limit at all:
  Finch's `:request_timeout` is left at its `:infinity` default.

  What is bounded, and what each bound means:

    * **Connecting to the agent** (5s, every call including the stream). A host
      that is down or unreachable never completes the TCP connect; failing fast
      there is what makes "the agent is unreachable" readable instead of arriving
      as a slow, unexplained `"timeout"`.

    * **The stream's silence** (15 min). Finch applies `:receive_timeout` *per
      chunk*, restarting the clock on every byte, so this is the longest the run
      may send NOTHING — not the longest it may run. It exists only because a
      half-open connection (killed pod, dropped NAT entry) never announces itself:
      without it a dead socket would hang the run forever with the UI spinning.
      Hitting it is treated as a lost connection, so the turn parks `:paused` and
      Continue resumes it on the same thread — the agent's work is not thrown away.

    * **The one-shot calls** (15s per attempt, one retry): create a thread, cancel
      a run, poll thread state. These are answered from the agent's own store, so
      slower than that means a sick server. None of them is in the research path.

  A reverse proxy in front of the agent has idle timeouts of its own, and those we
  cannot see from here: a run cut at a suspiciously round number of seconds with
  the agent still healthy is a proxy, not this module.
  """

  alias Sanbase.DeepResearch.{Config, EventParser, Failure, SSE}

  require Logger

  # -- the stream's budget (see the "Timeouts" section of the moduledoc) ----------

  # How long the stream may stay SILENT, not how long a run may take. Finch applies
  # `:receive_timeout` per chunk and restarts the clock on every byte that arrives
  # (`Mint.HTTP.recv/3` inside its receive loop), and the total-duration timeout
  # (`:request_timeout`) is left at its `:infinity` default, so a run is free to
  # take hours as long as it keeps emitting.
  #
  # A silent stretch is the model thinking, or a tool call that reports nothing
  # until it returns. 15 minutes is well past both; past that we assume a dead
  # socket, which a half-open connection (no FIN — killed pod, dropped NAT entry)
  # never tells us about. Not `:infinity` for exactly that reason: the run would
  # hang forever with the UI spinning on it.
  @stream_idle_timeout 900_000

  # -- the one-shot calls' budget -------------------------------------------------

  # Separate from the read timeout on purpose: a host that is down or unreachable
  # (agent not running, VPN off, wrong address) never completes the TCP connect,
  # and spending the full read timeout on that hides a connectivity problem behind
  # a slow, unexplained "timeout". Fails in seconds instead. Applies to the stream's
  # own connect too — only reaching the agent is bounded, never the research.
  @connect_timeout 5_000

  # One-shot calls (create, cancel, state poll) are answered from the agent's own
  # store, so anything slower than this is a sick server, not a slow one. Retried
  # once on a transport blip, which keeps the worst case at what a single attempt
  # used to cost.
  @request_timeout 15_000
  @request_retries 1

  # Fixed, rather than Req's exponential default, so the worst case below is
  # arithmetic instead of a guess: one quick retry is all a transport blip needs.
  @retry_delay 500

  # What ONE one-shot call can cost at worst: every attempt spending its connect
  # budget and then its read budget, plus the backoff between attempts. A caller
  # that wraps such a call in a task of its own has to outlast this, or it kills a
  # call that was still going. Nothing here bounds a run — see `@stream_idle_timeout`.
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
  Cancel an in-flight run. Returns `{:error, failure}` on failure — the thread is
  reused for later turns, so a failed cancel leaving the previous run alive is
  worth surfacing. The LiveView fires cancels from a supervised task and treats
  them as best-effort, but callers that care can react.
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
  Cancel every in-flight run on `thread_id`. Covers the early-cancel window: the
  user hits Stop before the stream has delivered a `run_id`, but the server-side
  run already exists — so look up the thread's active runs and cancel each.
  Best-effort (`:ok` regardless): individual cancel failures are logged by
  `cancel_run/2`.
  """
  @spec cancel_active_runs(String.t()) :: :ok
  def cancel_active_runs(thread_id) do
    case Req.get(url("/threads/#{thread_id}/runs"), oneshot_opts([])) do
      {:ok, %{status: status, body: runs}} when status in 200..299 and is_list(runs) ->
        # Cancel concurrently: sequential cancels stack their HTTP timeouts,
        # and a Stop should take effect on every run at once.
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
  Stream a run on `thread_id`, forwarding parsed events to `lv_pid` as
  `{:dra_event, ref, result}` messages during the stream. Blocks the calling
  process for as long as the run takes — hours, if the research takes hours; the
  only limit is how long it may stay silent (see "Timeouts" above). Run it via
  `start_async/3` so the LiveView keeps serving heartbeats. Returns the terminal
  status for `handle_async/3`.

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
          # Never retried, unlike the one-shot calls: a retry replays the request
          # and would start a SECOND run whose events interleave with the first's.
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

  # The shared shape of every non-streaming call: bounded, retried once.
  # `:transient` (rather than the default `:safe_transient`) retries the POSTs
  # too, which is safe for the calls we make with it — a retried create leaves at
  # most one unused empty thread behind, a repeated cancel is idempotent.
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

  # Attach the deploy's bearer token (if configured) and the connect timeout to a
  # request's options.
  defp request_opts(opts) do
    opts = Keyword.put(opts, :connect_options, timeout: @connect_timeout)

    case Config.auth_token() do
      nil -> opts
      token -> Keyword.put(opts, :auth, {:bearer, token})
    end
  end

  # The run payload carries the OpenRouter/Tavily API keys, so a non-local plain
  # HTTP base URL puts them on the wire in cleartext. On a deployed environment
  # (stage/prod) fail closed and refuse the run — except for cluster-internal
  # hosts (*.cluster.local), whose traffic never leaves the k8s network. In
  # local dev only warn — the default is localhost and a remote agent may sit
  # on a trusted network.
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
