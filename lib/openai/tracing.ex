defmodule Sanbase.OpenAI.Tracing do
  @moduledoc """
  Langfuse tracing helpers for OpenAI interactions.

  Each traced LLM call sends two ingestion batches: one on start (the trace,
  unless the caller passes an existing `:trace_id`, and the generation) and
  one on finish (the generation's output and token usage, plus the trace
  output when this call created the trace).

  Every event carries the Langfuse `environment`, taken from `:environment`
  in the opts or `environment/0`.
  """

  alias LangfuseSdk.Ingestor

  require Logger

  @default_trace_name "openai.question"
  @default_generation_name "openai.question.ask"

  @type context :: %{
          trace_id: String.t(),
          generation_id: String.t(),
          environment: String.t(),
          owns_trace?: boolean()
        }

  @spec start(term(), map()) :: {:ok, context()} | {:error, term()}
  def start(input, opts \\ %{}) do
    opts = Map.new(opts)

    if enabled?() do
      try do
        do_start(input, opts)
      rescue
        error ->
          Logger.warning("Langfuse tracing start crashed: #{inspect(error)}")
          {:error, {:tracing_crashed, error}}
      end
    else
      {:error, :langfuse_not_configured}
    end
  end

  @doc """
  Returns true when Langfuse SDK has host + keys configured.
  """
  @spec enabled?() :: boolean()
  def enabled?() do
    cfg = Application.get_all_env(:langfuse_sdk)

    is_binary(cfg[:host]) and cfg[:host] != "" and
      is_binary(cfg[:secret_key]) and cfg[:secret_key] != "" and
      is_binary(cfg[:public_key]) and cfg[:public_key] != ""
  end

  @doc """
  The Langfuse environment traces are filed under: `LANGFUSE_TRACING_ENVIRONMENT`
  when set, otherwise the deployment environment (`DEPLOYMENT_ENVIRONMENT`,
  "dev" by default).
  """
  @spec environment() :: String.t()
  def environment() do
    case System.get_env("LANGFUSE_TRACING_ENVIRONMENT") do
      env when env in [nil, ""] ->
        Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) || "dev"

      env ->
        env
    end
  end

  @doc """
  Creates (or updates, when `attrs` has an existing `:id`) a trace. `attrs`
  takes `:id`, `:name`, `:user_id`, `:session_id`, `:input`, `:output`,
  `:metadata`, `:tags` and `:environment`. Returns `{:ok, trace_id}`.
  """
  @spec upsert_trace(map()) :: {:ok, String.t()} | {:error, term()}
  def upsert_trace(attrs) do
    attrs = Map.put_new_lazy(attrs, :id, &UUID.uuid4/0)

    case ingest([trace_event(attrs)]) do
      :ok ->
        {:ok, attrs.id}

      {:error, reason} ->
        Logger.warning("Langfuse trace upsert failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Records an event observation on an existing trace. `attrs` takes `:name`,
  `:input`, `:output`, `:metadata` and `:environment`.
  """
  @spec log_event(String.t(), map()) :: :ok
  def log_event(trace_id, attrs) do
    body =
      compact(%{
        "id" => UUID.uuid4(),
        "traceId" => trace_id,
        "name" => attrs[:name],
        "startTime" => DateTime.utc_now(),
        "input" => attrs[:input],
        "output" => attrs[:output],
        "metadata" => attrs[:metadata],
        "level" => "DEFAULT",
        "environment" => attrs[:environment] || environment()
      })

    case ingest([envelope("event-create", body)]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Langfuse event create failed: #{inspect(reason)}")
        :ok
    end
  end

  @spec finalize(context() | term(), {:ok, map()} | {:error, term()}) :: :ok
  def finalize(%{generation_id: _} = ctx, result) do
    events =
      case result do
        {:ok, %{content: answer} = completion} ->
          [
            generation_update(ctx, %{
              "output" => %{"role" => "assistant", "content" => answer},
              "model" => completion[:model],
              "usageDetails" => usage_details(completion[:usage]),
              "costDetails" => cost_details(completion[:usage])
            })
            | trace_output(ctx, answer)
          ]

        # No answer text (e.g. a usage-only map): record what there is.
        {:ok, completion} when is_map(completion) ->
          [
            generation_update(ctx, %{
              "output" => Map.drop(completion, [:model, :usage]),
              "model" => completion[:model],
              "usageDetails" => usage_details(completion[:usage]),
              "costDetails" => cost_details(completion[:usage])
            })
          ]

        {:error, reason} ->
          [
            generation_update(ctx, %{
              "level" => "ERROR",
              "statusMessage" => format_error(reason)
            })
          ]
      end

    case ingest(events) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Langfuse tracing finalize failed: #{inspect(reason)}")
        :ok
    end
  end

  def finalize(_ctx, _result), do: :ok

  defp do_start(input, opts) do
    environment = opts[:environment] || environment()
    now = DateTime.utc_now()

    {trace_id, trace_events} =
      case opts[:trace_id] do
        trace_id when is_binary(trace_id) ->
          {trace_id, []}

        _ ->
          trace_id = UUID.uuid4()

          event =
            trace_event(%{
              id: trace_id,
              name: Map.get(opts, :trace_name, @default_trace_name),
              user_id: opts[:user_id],
              session_id: opts[:session_id],
              input: Map.get(opts, :trace_input, input),
              metadata: opts[:trace_metadata],
              tags: opts[:trace_tags],
              environment: environment,
              timestamp: now
            })

          {trace_id, [event]}
      end

    generation_id = UUID.uuid4()

    generation_event =
      envelope(
        "generation-create",
        compact(%{
          "id" => generation_id,
          "traceId" => trace_id,
          "name" => Map.get(opts, :generation_name, @default_generation_name),
          "startTime" => now,
          "input" => Map.get(opts, :generation_input, input),
          "metadata" => opts[:generation_metadata],
          "model" => opts[:model],
          "modelParameters" => opts[:model_parameters],
          "environment" => environment
        })
      )

    case ingest(trace_events ++ [generation_event]) do
      :ok ->
        {:ok,
         %{
           trace_id: trace_id,
           generation_id: generation_id,
           environment: environment,
           owns_trace?: trace_events != []
         }}

      {:error, reason} ->
        Logger.warning("Langfuse tracing start failed: #{inspect(reason)}")
        {:error, {:tracing_start_failed, reason}}
    end
  end

  defp trace_event(attrs) do
    body =
      compact(%{
        "id" => attrs.id,
        "timestamp" => attrs[:timestamp],
        "name" => attrs[:name],
        "userId" => attrs[:user_id],
        "sessionId" => attrs[:session_id],
        "input" => attrs[:input],
        "output" => attrs[:output],
        "metadata" => attrs[:metadata],
        "tags" => attrs[:tags],
        "environment" => attrs[:environment] || environment()
      })

    envelope("trace-create", body)
  end

  defp generation_update(ctx, fields) do
    body =
      %{
        "id" => ctx.generation_id,
        "traceId" => ctx.trace_id,
        "endTime" => DateTime.utc_now(),
        "environment" => ctx.environment
      }
      |> Map.merge(compact(fields))

    envelope("generation-update", body)
  end

  # A trace passed in by the caller is owned by the caller, which sets its
  # output itself.
  defp trace_output(%{owns_trace?: true} = ctx, answer) do
    [
      trace_event(%{
        id: ctx.trace_id,
        output: answer,
        environment: ctx.environment
      })
    ]
  end

  defp trace_output(_ctx, _answer), do: []

  # `Ingestor.ingest_payload/1` raises when a batch partially fails; tracing
  # must never break the traced call.
  defp ingest(events) do
    case Ingestor.ingest_payload(events) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp envelope(type, body) do
    %{"id" => UUID.uuid4(), "type" => type, "timestamp" => DateTime.utc_now(), "body" => body}
  end

  # Converts an OpenAI-style `usage` object to Langfuse usage details. Langfuse
  # prices each key separately, so cached input and reasoning output are split
  # out of `input` and `output` rather than counted twice.
  @doc false
  def usage_details(%{"prompt_tokens" => prompt, "completion_tokens" => completion} = usage)
      when is_integer(prompt) and is_integer(completion) do
    cached = get_in(usage, ["prompt_tokens_details", "cached_tokens"]) || 0
    reasoning = get_in(usage, ["completion_tokens_details", "reasoning_tokens"]) || 0

    %{
      "input" => prompt - cached,
      "input_cached_tokens" => cached,
      "output" => completion - reasoning,
      "output_reasoning_tokens" => reasoning,
      "total" => usage["total_tokens"] || prompt + completion
    }
  end

  def usage_details(_usage), do: nil

  # OpenRouter reports the request's USD cost in `usage.cost`.
  defp cost_details(%{"cost" => cost}) when is_number(cost), do: %{"total" => cost}
  defp cost_details(_usage), do: nil

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
