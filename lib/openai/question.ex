defmodule Sanbase.OpenAI.Question do
  @moduledoc """
  OpenAI question client using the GPT-4.1 model.
  """

  use Sanbase.OpenAI.Traced

  @base_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-5-nano"

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

    with {:ok, %{content: content}} <- request_completion(question, %{model: model}) do
      {:ok, content}
    end
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
           receive_timeout: 30_000,
           connect_options: [timeout: 30_000]
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
        {:error, "OpenAI API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
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
