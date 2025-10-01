defmodule Sanbase.AI.AcademyTracing do
  @moduledoc """
  Langfuse tracing helpers for Academy AI interactions.
  Handles trace creation, session grouping, and validation event logging.
  """

  alias LangfuseSdk.Ingestor
  require Logger

  @doc """
  Creates tracing options for the main answer generation.
  """
  def answer_tracing_opts(question, chunks_count, user_id, session_id, model) do
    %{
      model: model,
      user_id: user_id && to_string(user_id),
      session_id: session_id,
      trace_name: "academy.qa",
      generation_name: "academy.qa.answer",
      trace_metadata: %{
        "question" => question,
        "chunks_count" => chunks_count,
        "environment" => environment()
      },
      trace_tags: [environment(), "academy_qa"]
    }
  end

  @doc """
  Creates tracing options for suggestion generation.
  """
  def suggestions_tracing_opts(question, user_id, session_id, model) do
    %{
      model: model,
      user_id: user_id && to_string(user_id),
      session_id: session_id,
      trace_name: "academy.qa.suggestions",
      generation_name: "academy.qa.suggestions.generate",
      trace_metadata: %{
        "question" => question,
        "environment" => environment()
      },
      trace_tags: [environment(), "academy_qa", "suggestions"]
    }
  end

  @doc """
  Creates a trace for suggestions using the ingestion API.
  Returns {:ok, trace_id} or {:error, reason}.
  """
  def create_suggestions_trace(question, answer, tracing_opts) do
    trace_id = generate_trace_id(tracing_opts[:session_id], "suggestions")

    trace_event = %{
      "type" => "trace-create",
      "id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now(),
      "body" => %{
        "id" => trace_id,
        "name" => tracing_opts[:trace_name],
        "sessionId" => tracing_opts[:session_id],
        "userId" => tracing_opts[:user_id],
        "input" => %{"question" => question, "answer_preview" => String.slice(answer, 0, 200)},
        "metadata" => tracing_opts[:trace_metadata],
        "tags" => tracing_opts[:trace_tags],
        "environment" => environment(),
        "timestamp" => DateTime.utc_now()
      }
    }

    case Ingestor.ingest_payload(trace_event) do
      {:ok, _} -> {:ok, trace_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Logs suggestion validation results to Langfuse as an event.
  """
  def log_validation_event(
        trace_id,
        _session_id,
        user_id,
        question,
        raw_suggestions,
        validated_suggestions,
        validation_details,
        similarity_threshold
      ) do
    metadata = %{
      "question" => question,
      "raw_suggestions_count" => length(raw_suggestions),
      "validated_suggestions_count" => length(validated_suggestions),
      "similarity_threshold" => similarity_threshold,
      "validation_details" => validation_details,
      "final_suggestions" => validated_suggestions,
      "environment" => environment()
    }

    metadata = if user_id, do: Map.put(metadata, "user_id", to_string(user_id)), else: metadata

    event = %{
      "type" => "event-create",
      "id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now(),
      "body" => %{
        "id" => UUID.uuid4(),
        "name" => "academy.qa.suggestions.validation",
        "traceId" => trace_id,
        "metadata" => metadata,
        "input" => %{
          "raw_suggestions" => raw_suggestions
        },
        "output" => %{
          "validated_suggestions" => validated_suggestions
        },
        "level" => "DEFAULT",
        "environment" => environment(),
        "startTime" => DateTime.utc_now()
      }
    }

    case Ingestor.ingest_payload(event) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to log suggestion validation to Langfuse: #{inspect(reason)}")
        :ok
    end
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

  defp generate_trace_id(session_id, suffix) do
    base = "#{session_id}_#{suffix}_#{System.system_time(:millisecond)}"
    :crypto.hash(:sha256, base) |> Base.encode16(case: :lower) |> String.slice(0, 32)
  end

  defp environment do
    System.get_env("MIX_ENV") || System.get_env("RELEASE_ENV") || "dev"
  end
end
