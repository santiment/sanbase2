defmodule SanbaseWeb.Graphql.Resolvers.TwitterResolver do
  import SanbaseWeb.Graphql.Helpers.Async
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval

  alias Sanbase.Project

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
         {:ok, data} <- Sanbase.Twitter.last_record(twitter_name) do
      {:ok, data}
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
           calibrate(Sanbase.Twitter, twitter_name, from, to, interval, 60 * 60),
         {:ok, data} <-
           Sanbase.Twitter.timeseries_data(twitter_name, from, to, interval) do
      {:ok, data}
    else
      {:error, reason} ->
        {:error, "Cannot fetch twitter history data for slug #{slug}: #{reason}"}

      error ->
        {:error, "Cannot fetch twitter history data for slug #{slug}: #{inspect(error)}"}
    end
  end
end
