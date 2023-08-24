defmodule Sanbase.OpenAI do
  require Logger

  alias Sanbase.Utils.Config
  alias Sanbase.Discord.AiContext
  alias Sanbase.Discord.GptRouter

  def ai(prompt, params) do
    url = "#{metrics_hub_url()}/social_qa"

    do_request(url, prompt, params)
  end

  def docs(prompt, params) do
    url = "#{metrics_hub_url()}/docs"

    do_request(url, prompt, params)
  end

  def do_request(url, prompt, params) do
    start_time = System.monotonic_time(:second)
    {msg_id, params} = Map.pop(params, :msg_id)

    timeframe = params[:timeframe] || -1
    model = params[:model] || "gpt-4"
    sentiment = params[:sentiment] || false
    projects = params[:projects] || []

    case HTTPoison.post(
           url,
           Jason.encode!(%{
             question: prompt,
             timeframe: timeframe,
             model: model,
             sentiment: sentiment,
             projects: projects
           }),
           [{"Content-Type", "application/json"}],
           timeout: 240_000,
           recv_timeout: 240_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        end_time = System.monotonic_time(:second)
        elapsed_time = end_time - start_time

        body = Jason.decode!(body)

        params =
          params
          |> Map.put(:answer, body["answer"])
          |> Map.put(:question, prompt)
          |> Map.put(:tokens_request, body["tokens_request"])
          |> Map.put(:tokens_response, body["tokens_response"])
          |> Map.put(:tokens_total, body["tokens_total"])
          |> Map.put(:total_cost, body["total_cost"])
          |> Map.put(:elapsed_time, elapsed_time)
          |> Map.put(
            :prompt,
            "System:\n" <>
              body["prompt"]["system"] <> "\n\n" <> "User:\n" <> body["prompt"]["user"]
          )

        {:ok, ai_context} = AiContext.create(params)
        {:ok, body, ai_context}

      {:ok, %HTTPoison.Response{status_code: 500, body: body}} ->
        end_time = System.monotonic_time(:second)
        elapsed_time = end_time - start_time

        body = Jason.decode!(body)

        Logger.error("[id=#{msg_id}] Can't fetch docs: #{inspect(body)}")

        params =
          params
          |> Map.put(:error_message, body["error"] <> "\n\n --- \n\n" <> body["trace"])
          |> Map.put(:question, prompt)
          |> Map.put(:elapsed_time, elapsed_time)

        AiContext.create(params)
        {:error, "Can't fetch", nil}

      error ->
        end_time = System.monotonic_time(:second)
        elapsed_time = end_time - start_time
        Logger.error("[id=#{msg_id}] Can't fetch docs: #{inspect(error)}")

        params =
          params
          |> Map.put(:error_message, inspect(error))
          |> Map.put(:question, prompt)
          |> Map.put(:elapsed_time, elapsed_time)

        AiContext.create(params)
        {:error, "Can't fetch", nil}
    end
  end

  def threaded_docs(prompt, params) do
    url = "#{metrics_hub_url()}/docs"

    {msg_id, params} = Map.pop(params, :msg_id)
    context = AiContext.fetch_history_context(params, 5)

    start_time = System.monotonic_time(:second)

    case HTTPoison.post(
           url,
           Jason.encode!(%{question: prompt, messages: context}),
           [{"Content-Type", "application/json"}],
           timeout: 240_000,
           recv_timeout: 240_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        end_time = System.monotonic_time(:second)
        elapsed_time = end_time - start_time
        body = Jason.decode!(body)

        params =
          params
          |> Map.put(:answer, body["answer"])
          |> Map.put(:question, prompt)
          |> Map.put(:tokens_request, body["tokens_request"])
          |> Map.put(:tokens_response, body["tokens_response"])
          |> Map.put(:tokens_total, body["tokens_total"])
          |> Map.put(:total_cost, body["total_cost"])
          |> Map.put(:elapsed_time, elapsed_time)

        {:ok, ai_context} = AiContext.create(params)
        {:ok, body, ai_context}

      error ->
        end_time = System.monotonic_time(:second)
        elapsed_time = end_time - start_time
        Logger.error("[id=#{msg_id}] Can't fetch docs: #{inspect(error)}")

        params =
          params
          |> Map.put(:error_message, inspect(error))
          |> Map.put(:question, prompt)
          |> Map.put(:elapsed_time, elapsed_time)

        AiContext.create(params)
        {:error, "Can't fetch", nil}
    end
  end

  def route(question, msg_id) do
    url = "#{metrics_hub_url()}/route"
    default_route = "academy"

    start_time = System.monotonic_time(:second)

    case HTTPoison.post(
           url,
           Jason.encode!(%{question: question}),
           [{"Content-Type", "application/json"}],
           timeout: 15_000,
           recv_timeout: 15_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        end_time = System.monotonic_time(:second)
        elapsed_time = end_time - start_time
        body = Jason.decode!(body)

        case body["error"] do
          nil ->
            Logger.info(
              "[id=#{msg_id}] [elapsed=#{elapsed_time}] Route success: question=#{question} #{inspect(body)}"
            )

            GptRouter.create(%{
              question: question,
              route: body["route"],
              elapsed_time: elapsed_time,
              timeframe: body["timeframe"],
              scores: %{
                score_academy: body["score_academy"],
                score_twitter: body["score_twitter"]
              },
              sentiment: body["sentiment"],
              projects: body["projects"]
            })

            {:ok, body["route"], body["timeframe"], body["sentiment"], normalize_projects(body)}

          error ->
            GptRouter.create(%{
              question: question,
              error: inspect(error),
              elapsed_time: elapsed_time
            })

            Logger.error("[id=#{msg_id}] Route error: question=#{question} #{inspect(error)}")
            {:ok, default_route, -1}
        end

      error ->
        end_time = System.monotonic_time(:second)
        elapsed_time = end_time - start_time

        Logger.error(
          "[id=#{msg_id}] [elapsed=#{elapsed_time}] Route error: question=#{question} #{inspect(error)}"
        )

        GptRouter.create(%{question: question, error: inspect(error), elapsed_time: elapsed_time})
        {:ok, default_route, -1}
    end
  end

  def manage_pinecone_index() do
    if is_prod?() do
      url = "#{metrics_hub_url()}/manage_index"
      HTTPoison.post(url, Jason.encode!(%{hours: 1}), [{"Content-Type", "application/json"}])
    end

    :ok
  end

  def search_insights(query) do
    url = "#{metrics_hub_url()}/search_insights"

    HTTPoison.post(url, Jason.encode!(%{query: query}), [{"Content-Type", "application/json"}])
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body |> Jason.decode!()

      _ ->
        []
    end
  end

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

    chat(prompt, system_prompt: system_prompt, max_tokens: 500, temperature: 0.5)
    |> case do
      {:ok, result} -> {:ok, %{title: result["title"], description: result["description"]}}
      {:error, _error} -> {:error, "Could not generate title and description for this SQL query"}
    end
  end

  defp chat(prompt, opts \\ [], retries \\ 3) do
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

    case HTTPoison.post(
           "https://api.openai.com/v1/chat/completions",
           Jason.encode!(payload),
           headers,
           timeout: 60_000,
           recv_timeout: 60_000
         ) do
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

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end

  defp is_prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"

  @cryptos %{
    "eth" => ["eth", "ethereum"],
    "btc" => ["btc", "bitcoin"]
  }

  defp normalize_projects(body) do
    body["projects"]
    |> Enum.map(&String.downcase/1)
    |> Enum.flat_map(&crypto_project/1)
  end

  defp crypto_project(project) do
    Enum.reduce(@cryptos, [], fn {key, value}, acc ->
      if project == key, do: acc ++ value, else: acc
    end)
  end

  defp openai_api_key() do
    System.get_env("OPENAI_API_KEY")
  end
end
