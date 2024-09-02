defmodule Sanbase.DiscordBot.AiServer do
  require Logger

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.AiGenCode

  def summarize_channel(channel, args) do
    args = Map.merge(%{channel: channel, thread: nil}, args)
    do_summarize(args)
  end

  def summarize_thread(thread, args) do
    args = Map.merge(%{thread: thread, channel: nil}, args)
    do_summarize(args)
  end

  def do_summarize(params) do
    url = "#{ai_server_url()}/summarize"

    do_request_ai_server(url, params)
    |> case do
      {:ok, result} ->
        if result["error"] do
          {:error, result["error"]}
        else
          {:ok, result["summary"]}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # current version of bot
  def answer(question, discord_metadata \\ %{}) do
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
      route_blacklist: route_blacklist,
      metadata: discord_metadata
    }

    do_request_ai_server(url, ai_server_params)
    |> case do
      {:ok, result} ->
        {:ok, ai_context} = create_ai_context(result, question, discord_metadata)
        {:ok, ai_context, result}

      {:error, :elimit} ->
        AiContext.check_limits(discord_metadata)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # code generator bot
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

  # postgres indexing
  def manage_postgres_index() do
    if prod?() do
      url = "#{ai_server_url()}/postgres/index"
      HTTPoison.put(url, Jason.encode!(%{hours: 1}), [{"Content-Type", "application/json"}])
    end

    :ok
  end

  def manage_postgres_index2() do
    if prod?() do
      url = "#{ai_server_url()}/postgres/index2"
      HTTPoison.put(url, Jason.encode!(%{hours: 1}), [{"Content-Type", "application/json"}])
    end

    :ok
  end

  # testing
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
  defp do_request_ai_server(url, params) do
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

      {:ok, %HTTPoison.Response{status_code: 403, body: body}} ->
        Logger.error("url=#{url}, params=#{inspect(params)} status_code=403 body=#{body}")
        {:error, :elimit}

      error ->
        Logger.error("url=#{url}, params=#{inspect(params)} error=#{inspect(error)}")
        {:error, error}
    end
  end

  defp create_ai_context(result, question, discord_metadata) do
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

    AiContext.create(params)
  end

  defp ai_server_url() do
    System.get_env("AI_SERVER_URL")
  end

  defp prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"

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
  defp add_command(_), do: "!thread"
end
