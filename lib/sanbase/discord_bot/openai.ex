defmodule Sanbase.OpenAI do
  require Logger

  @doc """
  Generates a title and description based on a given SQL query using GPT-4.
  """
  @spec generate_from_sql(String.t()) :: {:ok, map()} | {:error, String.t()}
  def generate_from_sql(sql) do
    system_prompt =
      "You are a helpful assistant specialized in generating human-readable titles and descriptions based on ClickHouse SQL queries."

    prompt = """
    I need you to transform the following ClickHouse SQL queries into a human-readable title and description.
    Always return a JSON containing 'title' and 'description' fields.
    Important: Never return anything else besides the JSON.

    SQL: SELECT * FROM users WHERE age >= 21;
    {"title": "Fetch Adult Users", "description": "Retrieve all users who are 21 years old or above"}

    SQL: SELECT timestamp, from_address, to_address, amount from eth_transactions;
    {"title": "Retrieve Ethereum Transaction Details", "description": "Retrieve the timestamp, from_address, to_address, and amount details from all Ethereum transactions"}

    SQL: #{sql};
    """

    case chat(prompt, system_prompt: system_prompt, max_tokens: 500, temperature: 0.5) do
      {:ok, result} -> {:ok, %{title: result["title"], description: result["description"]}}
      {:error, _error} -> {:error, "Could not generate title and description for this SQL query"}
    end
  end

  # helpers
  defp chat(prompt, opts, retries \\ 3) do
    messages = [%{"role" => "user", "content" => prompt}]

    messages =
      case Keyword.get(opts, :system_prompt) do
        nil -> messages
        system_prompt -> [%{"role" => "system", "content" => system_prompt}] ++ messages
      end

    payload = %{
      "model" => Keyword.get(opts, :model, "gpt-4"),
      "messages" => messages,
      "max_tokens" => Keyword.get(opts, :max_tokens, 1000),
      "temperature" => Keyword.get(opts, :temperature, 0.0)
    }

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{openai_api_key()}"}
    ]

    http_response =
      HTTPoison.post(
        "https://api.openai.com/v1/chat/completions",
        Jason.encode!(payload),
        headers,
        timeout: 60_000,
        recv_timeout: 60_000
      )

    case http_response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok,
         Jason.decode!(body)["choices"]
         |> Enum.at(0)
         |> Map.get("message")
         |> Map.get("content")
         |> Jason.decode!()}

      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code != 200 ->
        error_msg =
          "[openai_chat] Received non-200 status code: #{status_code} for prompt: #{prompt}"

        Logger.error(error_msg)
        handle_retry(prompt, opts, retries, error_msg)

      {:error, %HTTPoison.Error{reason: reason}} ->
        error_msg = "[openai_chat] HTTP error: #{reason} for prompt: #{prompt}"
        Logger.error(error_msg)
        handle_retry(prompt, opts, retries, error_msg)
    end
  end

  defp handle_retry(_prompt, _opts, 0, error_message) do
    {:error, error_message}
  end

  defp handle_retry(prompt, opts, retries, _error_message) when retries > 0 do
    :timer.sleep(1000)
    chat(prompt, opts, retries - 1)
  end

  defp openai_api_key() do
    System.get_env("OPENAI_API_KEY")
  end
end
