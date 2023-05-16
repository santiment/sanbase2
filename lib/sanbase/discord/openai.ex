defmodule Sanbase.OpenAI do
  require Logger

  alias Sanbase.Utils.Config
  alias Sanbase.Discord.{AiContext, ThreadAiContext}

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

    case HTTPoison.post(
           url,
           Jason.encode!(%{question: prompt}),
           [{"Content-Type", "application/json"}],
           timeout: 120_000,
           recv_timeout: 120_000
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

        AiContext.create(params)
        {:ok, body}

      error ->
        Logger.error("[id=#{msg_id}] Can't fetch docs: #{inspect(error)}")
        {:error, "Can't fetch"}
    end
  end

  def threaded_docs(prompt, params) do
    url = "#{metrics_hub_url()}/docs"

    {msg_id, params} = Map.pop(params, :msg_id)
    context = ThreadAiContext.fetch_history_context(params, 5)

    start_time = System.monotonic_time(:second)

    case HTTPoison.post(
           url,
           Jason.encode!(%{question: prompt, messages: context}),
           [{"Content-Type", "application/json"}],
           timeout: 120_000,
           recv_timeout: 120_000
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

        {:ok, thread_db} = ThreadAiContext.create(params)
        {:ok, body, thread_db}

      error ->
        Logger.error("[id=#{msg_id}] Can't fetch docs: #{inspect(error)}")
        {:error, "Can't fetch", nil}
    end
  end

  def manage_pinecone_index() do
    if is_prod?() do
      url = "#{metrics_hub_url()}/manage_index"
      HTTPoison.post(url, Jason.encode!(%{hours: 1}), [{"Content-Type", "application/json"}])
    end

    :ok
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end

  defp is_prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"
end
