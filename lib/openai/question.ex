defmodule Sanbase.OpenAI.Question do
  @moduledoc """
  OpenAI question client using the GPT-4.1 model.
  """

  @base_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-4.1"

  @doc """
  Sends a question to OpenAI GPT-4.1 and returns the answer.

  ## Parameters
  - question: The question text to send to GPT-4.1

  ## Returns
  - {:ok, answer} on success where answer is the response text
  - {:error, reason} on failure
  """
  def ask(question) do
    body = build_request_body(question)

    case Req.post(@base_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{openai_apikey()}"},
             {"Content-Type", "application/json"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, String.trim(content)}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp build_request_body(question) do
    %{
      "model" => @model,
      "messages" => [
        %{
          "role" => "user",
          "content" => question
        }
      ],
      "max_tokens" => 1500,
      "top_p" => 0.05
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
