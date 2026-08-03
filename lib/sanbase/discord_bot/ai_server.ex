defmodule Sanbase.DiscordBot.AiServer do
  require Logger

  alias Sanbase.DiscordBot.AiContext

  # current version of bot
  def answer(question, discord_metadata) when is_map(discord_metadata) do
    url = "#{ai_server_url()}/question"

    route_blacklist =
      AiContext.check_limits(discord_metadata)
      |> case do
        :ok -> []
        {:error, _, _} -> ["twitter"]
      end

    messages = AiContext.fetch_history_context(discord_metadata, 10)

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
      |> Map.put(:function_called, result["function_called"])
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

  # prompt is a list of maps, each with 'role' and 'content' keys.
  # Role can be 'system', 'user', or 'assistant'. Content is a string.
  defp maybe_add_prompt(params, prompt) do
    if prompt do
      formatted_prompt =
        Enum.map_join(prompt, "\n\n", fn %{"role" => role, "content" => content} ->
          "#{String.capitalize(role)}:\n#{content}"
        end)

      Map.put(params, :prompt, formatted_prompt)
    else
      params
    end
  end

  defp add_command("twitter"), do: "!ai"
  defp add_command("academy"), do: "!thread"
  defp add_command(_), do: "!thread"
end
