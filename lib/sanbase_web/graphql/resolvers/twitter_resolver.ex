defmodule SanbaseWeb.Graphql.Resolvers.TwitterResolver do
  alias Sanbase.Model.Project
  alias Sanbase.ExternalServices.TwitterData.Store
  alias SanbaseWeb.Graphql.Helpers.Utils

  import SanbaseWeb.Graphql.Helpers.Async

  def twitter_data(_root, %{slug: slug}, _resolution) do
    calculate_twitter_data(slug)
  end

  def twitter_data(_root, %{ticker: ticker}, _resolution) do
    slug = Project.slug_by_ticker(ticker)
    calculate_twitter_data(slug)
  end

  def twitter_data(%Project{coinmarketcap_id: slug}, _args, _resolution) do
    async(fn -> calculate_twitter_data(slug) end)
  end

  defp calculate_twitter_data(slug) do
    with %Project{twitter_link: twitter_link, ticker: ticker} <- Project.by_slug(slug),
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
        root,
        %{ticker: ticker} = args,
        resolution
      ) do
    slug = Project.slug_by_ticker(ticker)
    args = args |> Map.delete(:ticker) |> Map.put(:slug, slug)
    history_twitter_data(root, args, resolution)
  end

  def history_twitter_data(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with %Project{twitter_link: twitter_link} <- Project.by_slug(slug),
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
        {:error, "Cannot fetch twitter history data for slug #{slug}: #{reason}"}

      error ->
        {:error, "Cannot fetch twitter history data for slug #{slug}: #{inspect(error)}"}
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
end
