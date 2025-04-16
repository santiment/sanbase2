defmodule Sanbase.TweetsApi do
  @moduledoc """
  Module for fetching tweets from the AI server
  """
  require Logger

  @doc """
  Fetches tweets from the AI server for the given number of hours
  Returns a list of tweets with information about the tweet
  """
  @spec fetch_tweets(integer()) :: {:ok, list(map())} | {:error, any()}
  def fetch_tweets(count \\ 1000) do
    url = "#{ai_server_url()}/tweets/recent?count=#{count}"

    HTTPoison.get(url, [{"Content-Type", "application/json"}],
      timeout: 15_000,
      recv_timeout: 15_000
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        tweets = Jason.decode!(body)["tweets"]
        {:ok, tweets}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Error fetching tweets. Status: #{status_code}, body: #{body}")
        {:error, "Error fetching tweets. Status: #{status_code}"}

      {:error, error} ->
        Logger.error("Error fetching tweets: #{inspect(error)}")
        {:error, "Error fetching tweets: #{inspect(error)}"}
    end
  end

  defp ai_server_url() do
    System.get_env("AI_SERVER_URL")
  end
end
