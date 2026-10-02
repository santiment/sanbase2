defmodule Sanbase.OpenAI.Question do
  @moduledoc """
  OpenAI question client. Defaults to the `gpt-6-luna` model with reasoning
  off; override per call via `tracing_opts.model` / `tracing_opts.reasoning_effort`.
  """

  require Logger

  use Sanbase.OpenAI.Traced

  @base_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-6-luna"
  # Sent only when the caller relies on the default model: gpt-6-luna otherwise
  # runs at its own default, "medium".
  @default_reasoning_effort "none"
  @max_retries 3
  @initial_backoff_ms 1_000
  @receive_timeout_ms 60_000

  @doc "The default model this client uses when none is passed in `tracing_opts`."
  @spec default_model() :: String.t()
  def default_model(), do: @model

  @doc """
  Sends a question to OpenAI GPT and returns the answer.

  ## Parameters
  - question: The question text to send to GPT
  - tracing_opts: Optional map with:
    - `:model` - OpenAI model to use (defaults to @model, with reasoning effort
      @default_reasoning_effort unless `:reasoning_effort` is given)
    - `:response_format` - OpenAI `response_format` payload (e.g. a JSON-schema
      map) to request structured output; omitted from the request when absent
    - `:reasoning_effort` - reasoning effort for reasoning models. gpt-6 takes
      "none" | "low" | "medium" | "high" | "xhigh"; the original gpt-5 models
      take "minimal" instead of "none". Omitted from the request when absent
      and `:model` is given. Use "none" (or "minimal") for simple extraction
      calls where reasoning latency dominates
    - `:user_id` - User ID for Langfuse trace
    - `:session_id` - Session ID for grouping traces
    - `:trace_metadata` - Additional metadata for the trace
    - `:generation_metadata` - Additional metadata for the generation

  ## Returns
  - {:ok, answer} on success where answer is the response text
  - {:error, reason} on failure

  ## Examples

      # Without tracing
      Question.ask("What is Elixir?")

      # With tracing
      Question.ask("What is Elixir?", %{model: "gpt-6-luna", user_id: "user123"})
  """
  deftraced ask(question) do
    request_opts =
      tracing_opts
      |> Map.take([:model, :response_format, :reasoning_effort])
      |> put_default_model()

    case request_with_retry(question, request_opts, 0) do
      {:ok, %{content: content}} ->
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_with_retry(question, request_opts, attempt)
       when attempt < @max_retries do
    case request_completion(question, request_opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, %Req.TransportError{reason: :closed}} ->
        backoff_ms = round(@initial_backoff_ms * :math.pow(2, attempt))

        warning_info = %{
          reason: :connection_closed,
          attempt: attempt + 1,
          max_retries: @max_retries,
          backoff_ms: backoff_ms,
          question_length: String.length(question),
          model: request_opts.model
        }

        Logger.warning("OpenAI connection closed, retrying: #{inspect(warning_info)}")

        Process.sleep(backoff_ms)
        request_with_retry(question, request_opts, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_with_retry(question, _request_opts, attempt)
       when attempt >= @max_retries do
    error_info = %{
      max_retries: @max_retries,
      question_length: String.length(question),
      attempt: attempt
    }

    Logger.error("OpenAI request failed after max retries: #{inspect(error_info)}")

    {:error, "Max retries exceeded for OpenAI request"}
  end

  defp request_completion(question, opts) do
    model = Map.get(opts, :model, @model)
    body = build_request_body(question, model, opts)

    case Req.post(@base_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{openai_apikey()}"},
             {"Content-Type", "application/json"}
           ],
           receive_timeout: @receive_timeout_ms
         ) do
      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => content}} | _]} = response
       }} ->
        trimmed = content |> to_string() |> String.trim()

        {:ok,
         %{
           content: trimmed,
           model: Map.get(response, "model", model),
           usage: Map.get(response, "usage"),
           response: response
         }}

      {:ok, %{status: status, body: body}} ->
        error_info = %{
          status: status,
          error: body,
          model: model,
          question_length: String.length(question)
        }

        Logger.error("OpenAI API error: #{inspect(error_info)}")

        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        error_info = %{
          error: reason,
          model: model,
          question_length: String.length(question),
          receive_timeout_ms: @receive_timeout_ms
        }

        Logger.error("OpenAI request failed: #{inspect(error_info)}")

        {:error, reason}
    end
  end

  defp build_request_body(question, model, opts) do
    %{
      "model" => model,
      "messages" => [
        %{
          "role" => "user",
          "content" => question
        }
      ]
    }
    |> maybe_put_body("response_format", Map.get(opts, :response_format))
    |> maybe_put_body("reasoning_effort", Map.get(opts, :reasoning_effort))
  end

  defp put_default_model(%{model: model} = opts) when is_binary(model), do: opts

  defp put_default_model(opts) do
    opts
    |> Map.put(:model, @model)
    |> Map.put_new(:reasoning_effort, @default_reasoning_effort)
  end

  defp maybe_put_body(body, _key, nil), do: body
  defp maybe_put_body(body, key, value), do: Map.put(body, key, value)

  @doc """
  Returns the OpenAI API key.
  Uses the same authentication mechanism as Sanbase.AI.Embedding.
  """
  def openai_apikey do
    System.get_env("OPENAI_API_KEY")
  end
end
