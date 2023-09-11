defmodule Sanbase.DiscordBot.AiServer do
  require Logger

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.GptRouter
  alias Sanbase.DiscordBot.AiGenCode

  def ai(prompt, params) do
    url = "#{ai_server_url()}/question/social"

    do_request(url, prompt, params)
  end

  def docs(prompt, params) do
    url = "#{ai_server_url()}/question/docs"

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

        params =
          if body["prompt"] do
            Map.put(
              params,
              :prompt,
              "System:\n" <>
                body["prompt"]["system"] <> "\n\n" <> "User:\n" <> body["prompt"]["user"]
            )
          else
            params
          end

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

  def generate_program(query, discord_metadata) do
    url = "#{ai_server_url()}/generate"

    do_request_ai_server(url, %{query: query})
    |> case do
      {:ok, result} ->
        params = %{
          parent_id: nil,
          question: query,
          answer: result["gpt_answer"],
          program: result["program"],
          program_result: result["program_result"],
          elapsed_time: result["elapsed_time"],
          is_from_vs: false
        }

        params = Map.merge(params, discord_metadata)

        {:ok, ai_gen_code} = AiGenCode.create(params)

        {:ok, ai_gen_code}

      {:error, error} ->
        {:error, error}
    end
  end

  def find_or_generate_program(query, discord_metadata) do
    url = "#{ai_server_url()}/find_or_generate"

    do_request_ai_server(url, %{query: query})
    |> case do
      {:ok, result} ->
        params = %{
          parent_id: nil,
          question: query,
          answer: result["gpt_answer"],
          program: result["program"],
          program_result: result["program_result"],
          elapsed_time: result["elapsed_time"],
          is_from_vs: result["is_from_vs"]
        }

        params = Map.merge(params, discord_metadata)

        {:ok, ai_gen_code} = AiGenCode.create(params)

        {:ok, ai_gen_code}

      {:error, _error} ->
        generate_program(query, discord_metadata)
    end
  end

  def change_program(ai_gen_code, changes, discord_metadata, chat_history \\ []) do
    url = "#{ai_server_url()}/change"

    do_request_ai_server(url, %{
      query: ai_gen_code.question,
      program: ai_gen_code.program,
      changes: changes,
      chat_history: chat_history
    })
    |> case do
      {:ok, result} ->
        params = %{
          parent_id: ai_gen_code.id,
          question: ai_gen_code.question,
          changes: changes,
          answer: result["gpt_answer"],
          program: result["program"],
          program_result: result["program_result"],
          elapsed_time: result["elapsed_time"]
        }

        params = Map.merge(params, discord_metadata)

        {:ok, ai_gen_code} = AiGenCode.create(params)

        {:ok, ai_gen_code}

      {:error, error} ->
        {:error, error}
    end
  end

  def save_program(ai_gen_code) do
    url = "#{ai_server_url()}/save"

    do_request_ai_server(url, %{query: ai_gen_code.question, program: ai_gen_code.program})
    |> case do
      {:ok, _} ->
        {:ok, ai_gen_code} = AiGenCode.change(ai_gen_code, %{is_saved_vs: true})
        {:ok, ai_gen_code}

      {:error, error} ->
        {:error, error}
    end
  end

  def do_request_ai_server(url, params) do
    start_time = System.monotonic_time(:second)

    response =
      HTTPoison.post(
        url,
        Jason.encode!(params),
        [{"Content-Type", "application/json"}],
        timeout: 240_000,
        recv_timeout: 240_000
      )

    end_time = System.monotonic_time(:second)
    elapsed_time = end_time - start_time

    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body = Jason.decode!(body)
        body = Map.put(body, "elapsed_time", elapsed_time)

        {:ok, body}

      error ->
        {:error, error}
    end
  end

  def threaded_docs(prompt, params) do
    url = "#{ai_server_url()}/question/docs"

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
    url = "#{ai_server_url()}/question/route"
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

  def answer(question, discord_metadata \\ {}) do
    url = "#{ai_server_url()}/question"

    route_blacklist =
      AiContext.check_limits(discord_metadata)
      |> case do
        :ok -> []
        {:error, _, _} -> ["twitter"]
      end

    messages = AiContext.fetch_history_context(discord_metadata, 5)

    ai_server_params = %{
      question: question,
      messages: messages,
      route_blacklist: route_blacklist
    }

    do_request_ai_server(url, ai_server_params)
    |> case do
      {:ok, result} ->
        answer = result["answer"]

        params =
          discord_metadata
          |> Map.put(:answer, answer["answer"])
          |> Map.put(:question, question)
          |> Map.put(:tokens_request, answer["tokens_request"])
          |> Map.put(:tokens_response, answer["tokens_response"])
          |> Map.put(:tokens_total, answer["tokens_total"])
          |> Map.put(:total_cost, answer["total_cost"])
          |> Map.put(:elapsed_time, result["elapsed_time"])
          |> Map.put(:route, result["route"])
          |> Map.put(:command, add_command(result["route"]["route"]))

        params = maybe_add_prompt(params, answer["prompt"])

        {:ok, ai_context} = AiContext.create(params)
        {:ok, ai_context, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def manage_pinecone_index() do
    if is_prod?() do
      url = "#{ai_server_url()}/pinecone/index"
      HTTPoison.put(url, Jason.encode!(%{hours: 1}), [{"Content-Type", "application/json"}])
    end

    :ok
  end

  def search_insights(query) do
    url = "#{ai_server_url()}/question/insights"

    HTTPoison.post(url, Jason.encode!(%{query: query}), [{"Content-Type", "application/json"}])
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body |> Jason.decode!()

      _ ->
        []
    end
  end

  # helpers

  defp ai_server_url() do
    System.get_env("AI_SERVER_URL")
  end

  defp is_prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"

  @cryptos %{
    "eth" => ["eth", "ethereum"],
    "btc" => ["btc", "bitcoin"]
  }

  def normalize_projects(route) do
    route["projects"]
    |> Enum.map(&String.downcase/1)
    |> Enum.flat_map(&crypto_project/1)
  end

  defp crypto_project(project) do
    Enum.reduce(@cryptos, [project], fn {key, value}, acc ->
      if project == key, do: acc ++ value, else: acc
    end)
    |> Enum.uniq()
  end

  defp maybe_add_prompt(params, prompt) do
    if prompt do
      prompt =
        "System:\n" <>
          prompt["system"] <> "\n\n" <> "User:\n" <> prompt["user"]

      Map.put(params, :prompt, prompt)
    else
      params
    end
  end

  defp add_command("twitter"), do: "!ai"
  defp add_command("academy"), do: "!thread"
end
