defmodule Sanbase.TweetsApi do
  @moduledoc """
  Module for fetching tweets from the AI server
  """
  require Logger

  @doc """
  Fetches tweets from the AI server for the given number of hours
  Returns a list of tweets with information about the tweet

  If an email is provided and it matches "maksim.b@santiment.net" or "tsvetozar.p@santiment.net",
  it first fetches tweets from `/tweets/maksim` and then from `/tweets/recent`.
  """
  @spec fetch_tweets(String.t() | nil) :: {:ok, list(map())} | {:error, any()}
  def fetch_tweets(email \\ nil) do
    cond do
      email in ["maksim.b@santiment.net", "tsvetozar.p@santiment.net"] ->
        with {:ok, maksim_tweets} <- fetch_from_endpoint("/tweets/maksim", 100),
             {:ok, recent_tweets} <- fetch_from_endpoint("/tweets/recent", 1000) do
          {:ok, maksim_tweets ++ recent_tweets}
        end

      true ->
        fetch_from_endpoint("/tweets/recent", 1000)
    end
  end

  defp fetch_from_endpoint(endpoint, count) do
    url = "#{ai_server_url()}#{endpoint}?count=#{count}"

    HTTPoison.get(url, [{"Content-Type", "application/json"}],
      timeout: 15_000,
      recv_timeout: 15_000
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        tweets = Jason.decode!(body)["tweets"]
        {:ok, tweets}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error(
          "Error fetching tweets from #{endpoint}. Status: #{status_code}, body: #{body}"
        )

        {:error, "Error fetching tweets from #{endpoint}. Status: #{status_code}"}

      {:error, error} ->
        Logger.error("Error fetching tweets from #{endpoint}: #{inspect(error)}")
        {:error, "Error fetching tweets from #{endpoint}: #{inspect(error)}"}
    end
  end

  defp ai_server_url() do
    System.get_env("AI_SERVER_URL")
  end
end
