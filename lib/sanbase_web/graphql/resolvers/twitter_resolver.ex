defmodule SanbaseWeb.Graphql.Resolvers.TwitterResolver do
  alias Sanbase.Model.Project
  alias Sanbase.Twitter.Store
  alias SanbaseWeb.Graphql.Helpers.Utils

  import SanbaseWeb.Graphql.Helpers.Async

  def twitter_data(_root, %{slug: slug}, _resolution) do
    calculate_twitter_data(slug)
  end

  def twitter_data(_root, %{ticker: ticker}, _resolution) do
    slug = Project.slug_by_ticker(ticker)
    calculate_twitter_data(slug)
  end

  def twitter_data(%Project{slug: slug}, _args, _resolution) do
    async(fn -> calculate_twitter_data(slug) end)
  end

  defp calculate_twitter_data(slug) do
    with %Project{} = project <- Project.by_slug(slug),
         {:ok, twitter_name} <- Project.twitter_handle(project),
         {datetime, followers_count} <- Store.last_record_for_measurement(twitter_name) do
      {:ok,
       %{
         datetime: datetime,
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
    with %Project{} = project <- Project.by_slug(slug),
         {:ok, twitter_name} <- Project.twitter_handle(project),
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
end
