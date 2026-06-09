defmodule Sanbase.OpenRouter.Question do
  @moduledoc """
  OpenRouter chat-completions client, drop-in compatible with
  `Sanbase.OpenAI.Question.ask/2`.

  Lets the Knowledge answer step alone be pointed at an OpenRouter-hosted
  model (e.g. DeepSeek) while embeddings and reranking stay on their own
  providers. Same `ask(question, tracing_opts)` contract: returns
  `{:ok, content}` / `{:error, reason}`, honours `:model` and
  `:response_format` from `tracing_opts`, and is wrapped with the same
  Langfuse tracing.

  Point the live answer path here with:

      config :sanbase, :knowledge_answer_client, Sanbase.OpenRouter.Question

  or per call: `Sanbase.Knowledge.answer_question(q, answer_client: __MODULE__)`.

  Authenticates with the `OPENROUTER_API_KEY` env var. The model defaults to
  `config :sanbase, Sanbase.OpenRouter.Question, model: "…"`, falling back to
  `@default_model`; override per call via `tracing_opts.model` (the Knowledge
  path forwards `:answer_model` there).
  """

  require Logger

  use Sanbase.OpenAI.Traced

  @base_url "https://openrouter.ai/api/v1/chat/completions"
  @default_model "deepseek/deepseek-v4-flash"
  @max_retries 3
  @initial_backoff_ms 1_000
  @receive_timeout_ms 60_000

  @doc """
  Sends a question to an OpenRouter model and returns the answer text.

  See `Sanbase.OpenAI.Question.ask/2`; `tracing_opts` accepts `:model` and
  `:response_format` in addition to the tracing keys.
  """
  deftraced ask(question) do
    model = Map.get(tracing_opts, :model) || configured_model()
    response_format = Map.get(tracing_opts, :response_format)

    case request_with_retry(question, model, response_format, 0) do
      {:ok, %{content: content}} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_with_retry(question, model, response_format, attempt)
       when attempt < @max_retries do
    case request_completion(question, model, response_format) do
      {:ok, result} ->
        {:ok, result}

      {:error, %Req.TransportError{reason: :closed}} ->
        backoff_ms = round(@initial_backoff_ms * :math.pow(2, attempt))

        Logger.warning(
          "OpenRouter connection closed, retrying: #{inspect(%{attempt: attempt + 1, max_retries: @max_retries, backoff_ms: backoff_ms, model: model})}"
        )

        Process.sleep(backoff_ms)
        request_with_retry(question, model, response_format, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_with_retry(question, _model, _response_format, attempt)
       when attempt >= @max_retries do
    Logger.error(
      "OpenRouter request failed after max retries: #{inspect(%{max_retries: @max_retries, question_length: String.length(question)})}"
    )

    {:error, "Max retries exceeded for OpenRouter request"}
  end

  defp request_completion(question, model, response_format) do
    api_key = openrouter_apikey()

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_openrouter_api_key}
    else
      do_request(question, model, response_format, api_key)
    end
  end

  defp do_request(question, model, response_format, api_key) do
    body = build_request_body(question, model, response_format)

    case Req.post(@base_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"Content-Type", "application/json"}
           ],
           receive_timeout: @receive_timeout_ms
         ) do
      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => content}} | _]} = response
       }} ->
        {:ok,
         %{
           content: content |> to_string() |> String.trim(),
           model: Map.get(response, "model", model),
           usage: Map.get(response, "usage"),
           response: response
         }}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "OpenRouter API error: #{inspect(%{status: status, error: body, model: model})}"
        )

        {:error, "OpenRouter API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("OpenRouter request failed: #{inspect(%{error: reason, model: model})}")
        {:error, reason}
    end
  end

  defp build_request_body(question, model, response_format) do
    %{
      "model" => model,
      "messages" => [%{"role" => "user", "content" => question}]
    }
    |> maybe_put_response_format(response_format)
  end

  defp maybe_put_response_format(body, nil), do: body
  defp maybe_put_response_format(body, format), do: Map.put(body, "response_format", format)

  @doc "The default model this client uses when none is passed in `tracing_opts`."
  @spec default_model() :: String.t()
  def default_model(), do: configured_model()

  @doc "The configured OpenRouter model, falling back to the module default."
  @spec configured_model() :: String.t()
  def configured_model() do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:model, @default_model)
  end

  @doc "The OpenRouter API key, read from the `OPENROUTER_API_KEY` env var."
  @spec openrouter_apikey() :: String.t() | nil
  def openrouter_apikey() do
    System.get_env("OPENROUTER_API_KEY")
  end
end
