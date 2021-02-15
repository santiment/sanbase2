defmodule SanbaseWeb.Graphql.Resolvers.ShortUrlResolver do
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_to_str: 1]
  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.SanbaseDataloader

  require Logger

  def create_short_url(_root, %{} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    do_create_short_url(args, current_user.id)
  end

  def create_short_url(_root, %{} = args, _resolution) do
    do_create_short_url(args, nil)
  end

  def get_full_url(_root, %{short_url: short_url}, _resolution) do
    case Sanbase.ShortUrl.get(short_url) do
      nil -> {:error, "Short url #{short_url} does not exist."}
      %Sanbase.ShortUrl{} = short_url -> {:ok, short_url}
    end
  end

  def short_url_id(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :comment_short_url_id, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :comment_short_url_id, id)}
    end)
  end

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :short_urls_comments_count, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :short_urls_comments_count, id) || 0}
    end)
  end

  # Private functions

  defp do_create_short_url(%{full_url: _} = args, user_id) do
    args = Map.put(args, :user_id, user_id)

    case Sanbase.ShortUrl.create(args) do
      {:ok, %Sanbase.ShortUrl{} = short_url} -> {:ok, short_url}
      {:error, error} -> {:error, changeset_errors_to_str(error)}
    end
  end
end
