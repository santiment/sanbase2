defmodule SanbaseWeb.Graphql.Resolvers.TwitterResolver do
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.ExternalServices.TwitterData.Store

  def twitter_data(_root, %{ticker: ticker}, _resolution) do
    with %Project{twitter_link: twitter_link} <- Repo.get_by(Project, ticker: ticker),
         twitter_name <- extract_twitter_name(twitter_link),
         {datetime, followers_count} <- Store.last_record_for_measurement(twitter_name) do
      {:ok, %{
        ticker: ticker,
        datetime: datetime,
        twitter_name: twitter_name,
        followers_count: followers_count
      }}
    else
      {:error, reason} ->
        {:error, "Cannot fetch twitter data for ticker #{ticker}: #{reason}"}

      _ ->
        {:error, "Cannot fetch twitter data for ticker #{ticker}"}
    end
  end

  def history_twitter_data(
        _root,
        %{ticker: ticker, from: from, to: to, interval: interval},
        _resolution
      ) do
    with %Project{twitter_link: twitter_link} <- Repo.get_by(Project, ticker: ticker),
         twitter_name <- extract_twitter_name(twitter_link),
         twitter_historical_data <-
           Store.all_records_for_measurement(twitter_name, from, to, interval) do
      result =
        twitter_historical_data
        |> Enum.map(fn {datetime, followers_count} ->
          %{datetime: datetime, followers_count: followers_count}
        end)

      {:ok, result}
    else
      {:error, reason} ->
        {:error, "Cannot fetch twitter data for ticker #{ticker}: #{reason}"}

      _ ->
        {:error, "Cannot fetch twitter data for ticker #{ticker}"}
    end
  end

  defp extract_twitter_name("https://twitter.com/" <> twitter_name) do
    String.split(twitter_name, "/") |> hd
  end
end