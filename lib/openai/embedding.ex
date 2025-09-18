defmodule Sanbase.OpenAI.Embedding do
  @moduledoc """
  OpenAI embedding client using the text-embedding-3-small model.
  """

  @base_url "https://api.openai.com/v1/embeddings"
  @model "text-embedding-3-small"

  @doc """
  Generates embeddings for the given text using OpenAI's text-embedding-3-small model.

  ## Parameters
  - text: The input text to embed
  - size: The size of the embedding vector (optional, model default is used if not provided)

  ## Returns
  - {:ok, embedding} on success where embedding is a list of floats
  - {:error, reason} on failure
  """
  def generate_embedding(text, size) when is_integer(size) do
    body = build_request_body(text, size)

    case Req.post(@base_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{openai_apikey()}"},
             {"Content-Type", "application/json"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"data" => [%{"embedding" => embedding} | _]}}} ->
        {:ok, embedding}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp build_request_body(text, size) do
    %{
      "input" => text,
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
