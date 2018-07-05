defmodule SanbaseWeb.Graphql.Resolvers.TwitterResolver do
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.ExternalServices.TwitterData.Store
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  import Ecto.Query
  import SanbaseWeb.Graphql.Helpers.Async

  def twitter_data(_root, %{ticker: ticker}, _resolution) do
    async(Cache.func(fn -> calculate_twitter_data(ticker) end, {:twitter_data, ticker}))
  end

  def twitter_data(%Project{ticker: ticker}, _args, _resolution) do
    async(Cache.func(fn -> calculate_twitter_data(ticker) end, {:twitter_data, ticker}))
  end

  defp calculate_twitter_data(ticker) do
    with {:ok, twitter_link} <- get_twitter_link(ticker),
         {:ok, twitter_name} <- extract_twitter_name(twitter_link),
         {datetime, followers_count} <- Store.last_record_for_measurement(twitter_name) do
      {:ok,
       %{
         ticker: ticker,
         datetime: datetime,
         twitter_name: twitter_name,
         followers_count: followers_count
       }}
    else
      _error ->
        {:ok, nil}
    end
  end

  def history_twitter_data(
        _root,
        %{ticker: ticker, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, twitter_link} <- get_twitter_link(ticker),
         {:ok, twitter_name} <- extract_twitter_name(twitter_link),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(Store, twitter_name, from, to, interval, 60 * 60),
         twitter_historical_data <-
           Store.all_records_for_measurement!(twitter_name, from, to, interval) do
      result =
        twitter_historical_data
        |> Enum.map(fn {datetime, followers_count} ->
          %{datetime: datetime, followers_count: followers_count}
        end)

      {:ok, result}
    else
      {:error, reason} ->
        {:error, "Cannot fetch twitter history data for ticker #{ticker}: #{reason}"}

      error ->
        {:error, "Cannot fetch twitter history data for ticker #{ticker}: #{inspect(error)}"}
    end
  end

  defp extract_twitter_name("https://twitter.com/" <> twitter_name = twitter_link) do
    case String.split(twitter_name, "/") |> hd do
      "" ->
        {:error,
         "Twitter name must not be empty or the twitter link has wrong format: #{twitter_link}"}

      name ->
        {:ok, name}
    end
  end

  defp extract_twitter_name(_), do: {:error, "Can't parse twitter link"}

  defp get_twitter_link(nil), do: nil

  defp get_twitter_link(ticker) do
    query =
      from(
        p in Project,
        where:
          p.ticker == ^ticker and not is_nil(p.twitter_link) and not is_nil(p.coinmarketcap_id),
        select: p.twitter_link
      )

    case Repo.all(query) do
      [] -> {:error, "There is no project with ticker #{ticker}"}
      [twitter_link | _] -> {:ok, twitter_link}
    end
  end
end
