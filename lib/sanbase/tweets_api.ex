defmodule Sanbase.TweetsApi do
  @moduledoc """
  Module for fetching tweets and price predictions from the AI server
  """
  require Logger
  alias Sanbase.Cache

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

  @doc """
  Fetches recent tweets for disagreement classification
  """
  @spec fetch_recent_tweets(keyword()) :: {:ok, list(map())} | {:error, any()}
  def fetch_recent_tweets(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    size = Keyword.get(opts, :size, 10)

    fetch_recent_tweets_from_api(hours, size)
  end

  @doc """
  Classifies a tweet text using both AI models
  """
  @spec classify_tweet(String.t()) :: {:ok, map()} | {:error, any()}
  def classify_tweet(tweet_text) do
    classify_tweet_with_api(tweet_text)
  end

  @doc """
  Fetches recent tweets and classifies them with disagreement detection
  """
  @spec fetch_and_classify_tweets(keyword()) :: {:ok, list(map())} | {:error, any()}
  def fetch_and_classify_tweets(opts \\ []) do
    case fetch_recent_tweets(opts) do
      {:ok, tweets} ->
        IO.puts("Classifying #{length(tweets)} tweets")

        classified_tweets =
          Enum.map(tweets, fn tweet ->
            case classify_tweet(tweet["text"]) do
              {:ok, classification} ->
                Map.put(tweet, "classification", classification)

              {:error, _} ->
                tweet
            end
          end)

        {:ok, classified_tweets}

      error ->
        error
    end
  end

  @doc """
  Fetches price predictions from the AI server
  Returns a list of price predictions with tweet information and prediction data

  If maksim: true is passed in options, adds maksim=true parameter to the request
  Responses are cached for 10 minutes
  """
  @spec fetch_price_predictions(keyword()) :: {:ok, list(map())} | {:error, any()}
  def fetch_price_predictions(opts \\ []) do
    maksim_filter = Keyword.get(opts, :maksim, false)

    cache_key =
      if maksim_filter do
        {"price_predictions_maksim", 600}
      else
        {"price_predictions_all", 600}
      end

    Cache.get_or_store(Cache.name(), cache_key, fn ->
      fetch_price_predictions_from_api(maksim_filter)
    end)
  end

  defp fetch_recent_tweets_from_api(hours, size) do
    url = "#{ai_server_url()}/tweets/recent?hours=#{hours}&count=#{size}"

    HTTPoison.get(url, [{"accept", "application/json"}],
      timeout: 30_000,
      recv_timeout: 30_000
    )
    |> handle_response("tweets")
  end

  defp classify_tweet_with_api(tweet_text) do
    url = "#{ai_server_url()}/classify"
    body = Jason.encode!(%{"tweet_text" => tweet_text})

    HTTPoison.post(
      url,
      body,
      [{"Content-Type", "application/json"}, {"accept", "application/json"}],
      timeout: 30_000,
      recv_timeout: 30_000
    )
    |> handle_classify_response()
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}, key) do
    case Jason.decode(body) do
      {:ok, %{^key => data}} -> {:ok, data}
      {:ok, decoded} -> {:ok, decoded}
      {:error, error} -> {:error, "JSON decode error: #{inspect(error)}"}
    end
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status_code, body: body}}, _key) do
    Logger.error("API Error. Status: #{status_code}, body: #{body}")
    {:error, "API Error. Status: #{status_code}"}
  end

  defp handle_response({:error, error}, _key) do
    Logger.error("HTTP Error: #{inspect(error)}")
    {:error, "HTTP Error: #{inspect(error)}"}
  end

  defp handle_classify_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, error} -> {:error, "JSON decode error: #{inspect(error)}"}
    end
  end

  defp handle_classify_response({:ok, %HTTPoison.Response{status_code: status_code, body: body}}) do
    Logger.error("Classification API Error. Status: #{status_code}, body: #{body}")
    {:error, "Classification API Error. Status: #{status_code}"}
  end

  defp handle_classify_response({:error, error}) do
    Logger.error("Classification HTTP Error: #{inspect(error)}")
    {:error, "Classification HTTP Error: #{inspect(error)}"}
  end

  defp fetch_price_predictions_from_api(maksim_filter) do
    endpoint = "/crypto/price-predictions"

    url =
      if maksim_filter do
        "#{ai_server_url()}#{endpoint}?maksim=true"
      else
        "#{ai_server_url()}#{endpoint}"
      end

    HTTPoison.get(url, [{"Content-Type", "application/json"}],
      timeout: 300_000,
      recv_timeout: 300_000
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        predictions = Jason.decode!(body)["predictions"]
        {:ok, predictions}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Error fetching price predictions. Status: #{status_code}, body: #{body}")

        {:error, "Error fetching price predictions. Status: #{status_code}"}

      {:error, error} ->
        Logger.error("Error fetching price predictions: #{inspect(error)}")
        {:error, "Error fetching price predictions: #{inspect(error)}"}
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
