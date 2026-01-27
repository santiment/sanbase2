defmodule SanbaseWeb.Graphql.Resolvers.TwitterResolver do
  import SanbaseWeb.Graphql.Helpers.Async

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
end
