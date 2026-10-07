defmodule Sanbase.AI.AcademyTracing do
  @moduledoc """
  Langfuse tracing helpers for Academy AI interactions.

  One `academy.qa` trace is created per answered question. The follow-up
  rewrite, the answer and the suggestions are generations on that trace, and
  the suggestion validation is an event on it. Traces of one chat share a
  session.
  """

  alias Sanbase.OpenAI.Tracing

  @trace_name "academy.qa"

  @type context :: %{
          trace_id: String.t() | nil,
          user_id: String.t() | nil,
          session_id: String.t() | nil,
          environment: String.t()
        }

  @doc """
  Starts the trace for answering `question`. Options: `:user_id`,
  `:session_id`, `:environment` (defaults to `Tracing.environment/0`).

  When tracing is off or the trace can't be created, `trace_id` is nil and
  each generation creates its own trace.
  """
  @spec start_trace(String.t(), keyword()) :: context()
  def start_trace(question, opts) do
    environment = Keyword.get(opts, :environment) || Tracing.environment()
    user_id = Keyword.get(opts, :user_id)

    ctx = %{
      trace_id: nil,
      user_id: user_id && to_string(user_id),
      session_id: Keyword.get(opts, :session_id),
      environment: environment
    }

    with true <- Tracing.enabled?(),
         {:ok, trace_id} <-
           Tracing.upsert_trace(%{
             name: @trace_name,
             user_id: ctx.user_id,
             session_id: ctx.session_id,
             input: question,
             tags: ["academy_qa"],
             environment: environment
           }) do
      %{ctx | trace_id: trace_id}
    else
      _ -> ctx
    end
  end

  @doc """
  Tracing options for a `Question.ask/2` call on the trace.
  """
  @spec generation_opts(context(), String.t(), String.t(), map()) :: map()
  def generation_opts(ctx, generation_name, model, metadata \\ %{}) do
    %{
      trace_id: ctx.trace_id,
      trace_name: @trace_name,
      generation_name: generation_name,
      generation_metadata: metadata,
      model: model,
      user_id: ctx.user_id,
      session_id: ctx.session_id,
      environment: ctx.environment
    }
  end

  @doc """
  Sets the trace output once the answer (and suggestions) are ready.
  """
  @spec finish_trace(context(), map() | String.t(), map()) :: :ok
  def finish_trace(ctx, output, metadata \\ %{})

  def finish_trace(%{trace_id: nil}, _output, _metadata), do: :ok

  def finish_trace(ctx, output, metadata) do
    Tracing.upsert_trace(%{
      id: ctx.trace_id,
      output: output,
      metadata: metadata,
      environment: ctx.environment
    })

    :ok
  end

  @doc """
  Logs suggestion validation results to Langfuse as an event on the trace.
  """
  @spec log_validation_event(context(), list(), list(), list(), number()) :: :ok
  def log_validation_event(%{trace_id: nil}, _raw, _validated, _details, _threshold), do: :ok

  def log_validation_event(
        ctx,
        raw_suggestions,
        validated_suggestions,
        validation_details,
        similarity_threshold
      ) do
    Tracing.log_event(ctx.trace_id, %{
      name: "academy.qa.suggestions.validation",
      input: %{"raw_suggestions" => raw_suggestions},
      output: %{"validated_suggestions" => validated_suggestions},
      metadata: %{
        "raw_suggestions_count" => length(raw_suggestions),
        "validated_suggestions_count" => length(validated_suggestions),
        "similarity_threshold" => similarity_threshold,
        "validation_details" => validation_details
      },
      environment: ctx.environment
    })
  end

  @doc """
  Generates a session ID for the entire chat conversation.
  """
  def generate_session_id(chat_id, user_id) do
    if chat_id do
      "chat_#{chat_id}"
    else
      base = "anon_#{user_id || "guest"}_#{System.system_time(:second)}"
      :crypto.hash(:sha256, base) |> Base.encode16() |> String.slice(0, 32)
    end
  end
end
