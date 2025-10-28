defmodule Sanbase.AI.Embedding.OpenAI do
  @moduledoc """
  OpenAI embedding client using the text-embedding-3-small model.
  """

  require Logger

  @behaviour Sanbase.AI.Embedding.Behavior

  @base_url "https://api.openai.com/v1/embeddings"
  @model "text-embedding-3-small"
  @max_retries 3
  @initial_backoff_ms 1_000
  @receive_timeout_ms 60_000

  @doc """
  Generates embeddings for the given text or list of texts using OpenAI's text-embedding-3-small model.

  ## Parameters
  - text: The input text to embed (string) or list of texts (list of strings)
  - size: The size of the embedding vector (optional, model default is used if not provided)

  ## Returns
  - For single text: {:ok, embedding} on success where embedding is a list of floats
  - For list of texts: {:ok, embeddings} on success where embeddings is a list of embedding lists
  - {:error, reason} on failure
  """
  def generate_embeddings(texts, size) when is_list(texts) and is_integer(size) do
    request_with_retry(texts, size, 0)
  end

  defp request_with_retry(texts, size, attempt) when attempt < @max_retries do
    case make_request(texts, size) do
      {:ok, %{"data" => data}} ->
        embeddings = Enum.map(data, fn %{"embedding" => embedding} -> embedding end)
        {:ok, embeddings}

      {:error, %Req.TransportError{reason: :closed}} ->
        backoff_ms = round(@initial_backoff_ms * :math.pow(2, attempt))

        Logger.warning(
          "OpenAI embeddings connection closed, retrying",
          %{
            attempt: attempt + 1,
            max_retries: @max_retries,
            backoff_ms: backoff_ms,
            texts_count: length(texts)
          }
        )

        Process.sleep(backoff_ms)
        request_with_retry(texts, size, attempt + 1)

      {:error, reason} ->
        Logger.error("OpenAI embedding request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp request_with_retry(texts, _size, attempt) when attempt >= @max_retries do
    Logger.error(
      "OpenAI embeddings request failed after max retries",
      %{
        max_retries: @max_retries,
        texts_count: length(texts)
      }
    )

    {:error, "Max retries exceeded for OpenAI embeddings request"}
  end

  # Private functions

  defp make_request(texts, size) do
    body = build_request_body(texts, size)

    case Req.post(@base_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{openai_apikey()}"},
             {"Content-Type", "application/json"}
           ],
           receive_timeout: @receive_timeout_ms
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request_body(text_or_texts, size) do
    %{
      "input" => text_or_texts,
      "model" => @model,
      "dimensions" => size
    }
  end

  @doc """
  Returns the OpenAI API key.
  Implementation to be provided.
  """
  def openai_apikey do
    System.get_env("OPENAI_API_KEY")
  end
end
