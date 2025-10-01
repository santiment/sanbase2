defmodule Sanbase.OpenAI.Tracing do
  @moduledoc """
  Langfuse tracing helpers for OpenAI interactions.
  """

  alias LangfuseSdk
  alias LangfuseSdk.Ingestor
  alias LangfuseSdk.Tracing.{Generation, Trace}

  require Logger

  @default_trace_name "openai.question"
  @default_generation_name "openai.question.ask"

  @spec start(term(), map()) ::
          {:ok, %{trace: Trace.t(), generation: Generation.t()}} | {:error, term()}
  def start(input, opts \\ %{}) do
    opts = Map.new(opts)

    with {:ok, trace} <- ensure_trace(opts, input),
         {:ok, generation} <- create_generation(trace, input, opts) do
      {:ok, %{trace: trace, generation: generation}}
    end
  end

  @spec finalize(
          %{optional(:trace) => Trace.t(), generation: Generation.t()},
          {:ok, map()} | {:error, term()}
        ) :: :ok
  def finalize(%{trace: trace, generation: generation}, result) do
    do_finalize(trace, generation, result)
  end

  def finalize(_ctx, _result), do: :ok

  defp do_finalize(trace, generation, {:ok, %{content: answer} = completion}) do
    Logger.debug("Finalizing trace #{trace.id} with answer")

    metadata = merge_metadata(generation.metadata, %{"status" => "ok"})

    updated_generation = %{
      generation
      | end_time: DateTime.utc_now(),
        output: %{"role" => "assistant", "content" => answer},
        metadata: metadata,
        usage: build_usage(completion),
        model: completion.model || generation.model
    }

    update_generation(updated_generation)
    update_trace_output(trace, answer)
  end

  defp do_finalize(_trace, generation, {:error, reason}) do
    metadata =
      merge_metadata(generation.metadata, %{
        "status" => "error",
        "error" => format_error(reason)
      })

    updated_generation = %{
      generation
      | end_time: DateTime.utc_now(),
        status_message: format_error(reason),
        metadata: metadata
    }

    update_generation(updated_generation)
  end

  defp ensure_trace(%{trace_id: trace_id}, _input) when is_binary(trace_id) do
    {:ok, %Trace{id: trace_id}}
  end

  defp ensure_trace(opts, input) do
    # If environment is provided in opts, we need to create the trace via ingestion API
    # to support the environment field (not available in Trace struct)
    environment =
      Map.get(opts, :environment) || Map.get(opts, :trace_metadata, %{})["environment"]

    if environment do
      create_trace_with_environment(opts, input, environment)
    else
      create_trace_without_environment(opts, input)
    end
  end

  defp create_trace_without_environment(opts, input) do
    trace_attrs =
      opts
      |> Map.get(:trace, %{})
      |> Map.put_new(:name, Map.get(opts, :trace_name, @default_trace_name))
      |> maybe_put(:user_id, opts[:user_id])
      |> maybe_put(:input, Map.get(opts, :trace_input, input))
      |> maybe_put(:metadata, Map.get(opts, :trace_metadata))
      |> maybe_put(:tags, Map.get(opts, :trace_tags))
      |> maybe_put(:session_id, Map.get(opts, :session_id))

    trace = Trace.new(compact(trace_attrs))

    case LangfuseSdk.create(trace) do
      {:ok, _} ->
        updated_trace = trace |> maybe_add_trace_metadata(opts) |> maybe_add_trace_input(input)
        audit_trace(updated_trace)
        maybe_update_trace(updated_trace, trace)
        {:ok, updated_trace}

      {:error, reason} ->
        Logger.warning("Langfuse trace create failed: #{inspect(reason)}")
        {:error, {:trace_create_failed, reason}}
    end
  end

  defp create_trace_with_environment(opts, input, environment) do
    trace_id = Map.get(opts, :trace_id) || UUID.uuid4()

    trace_event = %{
      "type" => "trace-create",
      "id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now(),
      "body" => %{
        "id" => trace_id,
        "name" => Map.get(opts, :trace_name, @default_trace_name),
        "sessionId" => Map.get(opts, :session_id),
        "userId" => opts[:user_id],
        "input" => Map.get(opts, :trace_input, input),
        "metadata" => Map.get(opts, :trace_metadata),
        "tags" => Map.get(opts, :trace_tags),
        "environment" => environment,
        "timestamp" => DateTime.utc_now()
      }
    }

    case Ingestor.ingest_payload(trace_event) do
      {:ok, _} ->
        # Return a minimal Trace struct for compatibility
        trace = %Trace{
          id: trace_id,
          name: Map.get(opts, :trace_name, @default_trace_name),
          user_id: opts[:user_id],
          session_id: Map.get(opts, :session_id),
          input: Map.get(opts, :trace_input, input),
          metadata: Map.get(opts, :trace_metadata),
          tags: Map.get(opts, :trace_tags)
        }

        audit_trace(trace)
        {:ok, trace}

      {:error, reason} ->
        Logger.warning("Langfuse trace create failed: #{inspect(reason)}")
        {:error, {:trace_create_failed, reason}}
    end
  end

  defp create_generation(trace, input, opts) do
    now = DateTime.utc_now()

    generation_attrs =
      opts
      |> Map.get(:generation, %{})
      |> Map.put(:trace_id, trace.id)
      |> Map.put_new(:name, Map.get(opts, :generation_name, @default_generation_name))
      |> Map.put_new(:metadata, Map.get(opts, :generation_metadata))
      |> Map.put(:input, Map.get(opts, :generation_input, input))
      |> Map.put(:model, opts[:model])
      |> Map.put(:model_parameters, Map.get(opts, :model_parameters))
      |> Map.put_new(:start_time, now)
      |> Map.put_new(:completion_start_time, now)

    generation = Generation.new(compact(generation_attrs))

    case LangfuseSdk.create(generation) do
      {:ok, _} ->
        {:ok, generation}

      {:error, reason} ->
        Logger.warning("Langfuse generation create failed: #{inspect(reason)}")
        {:error, {:generation_create_failed, reason}}
    end
  end

  defp update_generation(generation) do
    case LangfuseSdk.update(generation) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Langfuse generation update failed: #{inspect(reason)}")
        :ok
    end
  end

  defp update_trace_output(%Trace{} = trace, answer) do
    Logger.debug("Updating trace #{trace.id} with output")

    trace_event = %{
      "type" => "trace-create",
      "id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now(),
      "body" => %{
        "id" => trace.id,
        "output" => answer
      }
    }

    case Ingestor.ingest_payload(trace_event) do
      {:ok, _} ->
        Logger.debug("Successfully updated trace #{trace.id} output")
        :ok

      {:error, reason} ->
        Logger.warning("Langfuse trace output update failed: #{inspect(reason)}")
        :ok
    end
  end

  defp audit_trace(_trace), do: :ok

  defp maybe_add_trace_metadata(trace, opts) do
    metadata = sanitize_metadata(Map.get(opts, :trace_metadata))

    if metadata in [%{}, nil] do
      trace
    else
      %{trace | metadata: merge_metadata(trace.metadata, metadata)}
    end
  end

  defp maybe_add_trace_input(trace, input) do
    if input in [nil, []] do
      trace
    else
      %{trace | input: input}
    end
  end

  defp maybe_update_trace(updated_trace, original_trace) do
    if trace_changes?(updated_trace, original_trace) do
      changes = %{}

      changes =
        if updated_trace.metadata != original_trace.metadata,
          do: Map.put(changes, "metadata", updated_trace.metadata),
          else: changes

      changes =
        if updated_trace.input != original_trace.input,
          do: Map.put(changes, "input", updated_trace.input),
          else: changes

      trace_event = %{
        "type" => "trace-create",
        "id" => UUID.uuid4(),
        "timestamp" => DateTime.utc_now(),
        "body" => Map.put(changes, "id", updated_trace.id)
      }

      case Ingestor.ingest_payload(trace_event) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Langfuse trace update failed: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end

  defp trace_changes?(%Trace{} = updated, %Trace{} = original) do
    Map.take(updated, [:metadata, :input]) != Map.take(original, [:metadata, :input])
  end

  defp build_usage(%{usage: usage}) when is_map(usage), do: usage
  defp build_usage(_), do: nil

  defp sanitize_metadata(nil), do: %{}
  defp sanitize_metadata(%{} = metadata), do: metadata
  defp sanitize_metadata(_), do: %{}

  defp merge_metadata(nil, additions), do: additions

  defp merge_metadata(metadata, additions) when is_map(metadata) do
    Map.merge(metadata, additions)
  end

  defp merge_metadata(_metadata, additions), do: additions

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put_new(map, key, value)
end
