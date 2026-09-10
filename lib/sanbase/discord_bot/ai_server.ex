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

    start_time = System.monotonic_time(:second)

    do_request_ai_server(url, ai_server_params)
    |> case do
      {:ok, result} ->
        {:ok, ai_context} = create_ai_context(result, question, discord_metadata)
        {:ok, ai_context, result}

      {:error, :elimit} ->
        # The AI server rejected the call on its own limits. Nothing was spent
        # and the user gets a limit message, so no row is written.
        AiContext.check_limits(discord_metadata)

      {:error, reason} ->
        # Previously this returned without touching the database, so a failed
        # question left no row at all and could only be found in the logs.
        record_failed_question(
          question,
          discord_metadata,
          reason,
          System.monotonic_time(:second) - start_time
        )

        {:error, reason}
    end
  end

  defp record_failed_question(question, discord_metadata, reason, elapsed_time) do
    params =
      discord_metadata
      |> Map.put(:question, question)
      |> Map.put(:status, AiContext.error_status())
      |> Map.put(:error_message, failure_reason(reason))
      |> Map.put(:elapsed_time, elapsed_time / 1)

    case AiContext.create(params) do
      {:ok, ai_context} ->
        {:ok, ai_context}

      {:error, changeset} ->
        Logger.error("Could not record failed AI question: #{inspect(changeset.errors)}")
        :error
    end
  end

  # `inspect/1` on an HTTPoison error is verbose and unstable; keep it short
  # enough to read in a query result but specific enough to group by.
  defp failure_reason({:ok, %HTTPoison.Response{status_code: status_code}}),
    do: "ai_server_http_#{status_code}"

  defp failure_reason({:error, %HTTPoison.Error{reason: reason}}),
    do: "ai_server_transport_#{inspect(reason)}"

  defp failure_reason(reason), do: String.slice(inspect(reason), 0, 500)

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
      # Diagnostics the AI server reports about how the answer was produced.
      # A "degraded" row means the user got an answer, but from a fallback.
      |> Map.put(:status, result["status"] || AiContext.ok_status())
      |> Map.put(:qa_engine, result["qa_engine"])
      |> Map.put(:v2_fallback, result["v2_fallback"] || false)
      |> Map.put(:rephrased_question, result["rephrased_question"])
      |> Map.put(:tools_used, result["tools_used"] || [])
      |> Map.put(:langfuse_trace_id, result["trace_id"])
      |> Map.put(:error_message, result["error_message"])

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
