defmodule Sanbase.OpenAI.Question do
  @moduledoc """
  OpenAI question client using the GPT-4.1 model.
  """

  use Sanbase.OpenAI.Traced

  @base_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-5-nano"
  @max_retries 3
  @initial_backoff_ms 1_000
  @receive_timeout_ms 60_000

  @doc """
  Sends a question to OpenAI GPT and returns the answer.

  ## Parameters
  - question: The question text to send to GPT
  - tracing_opts: Optional map with:
    - `:model` - OpenAI model to use (defaults to @model)
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
      Question.ask("What is Elixir?", %{model: "gpt-4", user_id: "user123"})
  """
  deftraced ask(question) do
    model = Map.get(tracing_opts, :model, @model)

    case request_with_retry(question, model, 0) do
      {:ok, %{content: content}} ->
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_with_retry(question, model, attempt) when attempt < @max_retries do
    case request_completion(question, %{model: model}) do
      {:ok, result} ->
        {:ok, result}

      {:error, %Req.TransportError{reason: :closed}} ->
        require Logger
        backoff_ms = round(@initial_backoff_ms * :math.pow(2, attempt))

        Logger.warning(
          "OpenAI connection closed, retrying",
          %{
            attempt: attempt + 1,
            max_retries: @max_retries,
            backoff_ms: backoff_ms,
            question_length: String.length(question)
          }
        )

        Process.sleep(backoff_ms)
        request_with_retry(question, model, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_with_retry(question, _model, attempt) when attempt >= @max_retries do
    require Logger

    Logger.error(
      "OpenAI request failed after max retries",
      %{
        max_retries: @max_retries,
        question_length: String.length(question)
      }
    )

    {:error, "Max retries exceeded for OpenAI request"}
  end

  defp request_completion(question, opts) do
    model = Map.get(opts, :model, @model)
    body = build_request_body(question, model)

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
        require Logger

        Logger.error(
          "OpenAI API error",
          %{
            status: status,
            error: inspect(body),
            model: model,
            question_length: String.length(question)
          }
        )

        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        require Logger

        Logger.error(
          "OpenAI request failed",
          %{
            error: inspect(reason),
            model: model,
            question_length: String.length(question),
            receive_timeout_ms: @receive_timeout_ms
          }
        )

        {:error, reason}
    end
  end

  defp build_request_body(question, model) do
    %{
      "model" => model,
      "messages" => [
        %{
          "role" => "user",
          "content" => question
        }
      ]
    }
  end

  @doc """
  Returns the OpenAI API key.
  Uses the same authentication mechanism as Sanbase.AI.Embedding.
  """
  def openai_apikey do
    System.get_env("OPENAI_API_KEY")
  end
end
