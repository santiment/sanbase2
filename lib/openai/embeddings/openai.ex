defmodule Sanbase.AI.Embedding.OpenAI do
  @moduledoc """
  OpenAI embedding client using the text-embedding-3-small model.
  """

  require Logger

  @behaviour Sanbase.AI.Embedding.Behavior

  @base_url "https://api.openai.com/v1/embeddings"
  @model "text-embedding-3-small"
  @max_retries 12
  @initial_backoff_ms 100
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
  def generate_embeddings(texts, _size) when is_list(texts) do
    request_with_retry(texts, 0)
  end

  @doc """
  Generates embeddings without retry logic. Useful for testing and debugging.

  Returns the same format as `generate_embeddings/2` but without automatic retries.
  """
  def generate_embeddings_without_retry(texts, _size) when is_list(texts) do
    case make_request(texts) do
      {:ok, %{"data" => data}} ->
        embeddings = Enum.map(data, fn %{"embedding" => embedding} -> embedding end)
        {:ok, embeddings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_with_retry(texts, attempt) when attempt < @max_retries do
    case make_request(texts) do
      {:ok, %{"data" => data}} ->
        embeddings = Enum.map(data, fn %{"embedding" => embedding} -> embedding end)
        {:ok, embeddings}

      {:error, %Req.TransportError{reason: :closed}} ->
        backoff_ms = @initial_backoff_ms + attempt * 100

        warning_info = %{
          reason: :connection_closed,
          attempt: attempt + 1,
          max_retries: @max_retries,
          backoff_ms: backoff_ms,
          texts_count: length(texts)
        }

        Logger.warning("OpenAI embeddings connection closed, retrying: #{inspect(warning_info)}")

        Process.sleep(backoff_ms)
        request_with_retry(texts, attempt + 1)

      {:error, reason} ->
        error_info = %{
          reason: reason,
          texts_count: length(texts)
        }

        Logger.error("OpenAI embedding request failed: #{inspect(error_info)}")
        {:error, reason}
    end
  end

  defp request_with_retry(texts, attempt) when attempt >= @max_retries do
    error_info = %{
      max_retries: @max_retries,
      texts_count: length(texts),
      attempt: attempt
    }

    Logger.error("OpenAI embeddings request failed after max retries: #{inspect(error_info)}")

    {:error, "Max retries exceeded for OpenAI embeddings request"}
  end

  @doc """
  Makes an embedding request and returns both the result and response headers.

  Returns `{:ok, response_body, headers}` on success or `{:error, reason, headers}` on failure.
  Headers may be empty if the request failed before receiving a response.
  """
  def make_request_with_headers(texts) do
    params = build_request_body(texts)

    req =
      Req.new(
        base_url: @base_url,
        json: params,
        headers: [
          {"Authorization", "Bearer #{openai_apikey()}"},
          {"Content-Type", "application/json"}
        ],
        receive_timeout: @receive_timeout_ms
      )

    case Req.post(req) do
      {:ok, %{status: 200, body: response_body, headers: headers}} ->
        {:ok, response_body, headers}

      {:ok, %{status: status, body: body, headers: headers}} ->
        {:error, "OpenAI API error: #{status} - #{inspect(body)}", headers}

      {:error, reason} ->
        {:error, reason, []}
    end
  end

  # Private functions

  defp make_request(texts) do
    params = build_request_body(texts)

    req =
      Req.new(
        base_url: @base_url,
        json: params,
        headers: [
          {"Authorization", "Bearer #{openai_apikey()}"},
          {"Content-Type", "application/json"}
        ],
        receive_timeout: @receive_timeout_ms
      )
      |> Req.Request.append_request_steps(
        debug_request: fn request ->
          request_debug = %{
            method: request.method,
            url: request.url,
            params: request.options
          }

          Logger.warning("OpenAI Embedding Request: #{inspect(request_debug)}")
          request
        end
      )
      |> Req.Request.append_response_steps(
        debug_response: fn {request, response} ->
          response_debug = %{
            status: response.status,
            headers: extract_debugging_headers(response.headers)
          }

          Logger.warning("OpenAI Embedding Response: #{inspect(response_debug)}")
          {request, response}
        end
      )

    case Req.post(req) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request_body(text_or_texts) do
    input =
      if is_list(text_or_texts) and length(text_or_texts) == 1 do
        hd(text_or_texts)
      else
        text_or_texts
      end

    %{
      input: input,
      model: @model,
      encoding_format: "float"
    }
  end

  @doc """
  Extracts debugging headers from OpenAI API responses.

  Returns a map with relevant debugging information including:
  - x-request-id
  - openai-organization
  - openai-processing-ms
  - openai-version
  - Rate limiting headers (limit, remaining, reset for requests and tokens)
  """
  def extract_debugging_headers(headers) do
    header_map =
      headers
      |> Enum.into(%{}, fn {key, value} -> {String.downcase(key), value} end)

    %{
      request_id: header_map["x-request-id"],
      organization: header_map["openai-organization"],
      processing_ms: header_map["openai-processing-ms"],
      version: header_map["openai-version"],
      rate_limit_limit_requests: header_map["x-ratelimit-limit-requests"],
      rate_limit_limit_tokens: header_map["x-ratelimit-limit-tokens"],
      rate_limit_remaining_requests: header_map["x-ratelimit-remaining-requests"],
      rate_limit_remaining_tokens: header_map["x-ratelimit-remaining-tokens"],
      rate_limit_reset_requests: header_map["x-ratelimit-reset-requests"],
      rate_limit_reset_tokens: header_map["x-ratelimit-reset-tokens"]
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
