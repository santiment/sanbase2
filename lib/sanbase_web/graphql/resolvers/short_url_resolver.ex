defmodule SanbaseWeb.Graphql.Resolvers.ShortUrlResolver do
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  require Logger

  def create_short_url(_root, %{} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    do_create_short_url(args, current_user.id)
  end

  def create_short_url(_root, %{} = args, _resolution) do
    do_create_short_url(args, nil)
  end

  def update_short_url(_root, %{short_url: short_url} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    params = Map.delete(args, :short_url)
    Sanbase.ShortUrl.update(current_user.id, short_url, params)
  end

  def update_short_url(_root, _args, _resolution) do
    {:error,
     """
     Only authenticated users can update Short URLs.
     Short URLs created by anonymous users cannot be updated.
     """}
  end

  def get_full_url(_root, %{short_url: short_url}, _resolution) do
    case Sanbase.ShortUrl.get(short_url) do
      nil -> {:error, "Short url #{short_url} does not exist."}
      %Sanbase.ShortUrl{} = short_url -> {:ok, short_url}
    end
  end

  # Private functions

  defp do_create_short_url(%{full_url: _} = args, user_id) do
    args = Map.put(args, :user_id, user_id)

    case Sanbase.ShortUrl.create(args) do
      {:ok, %Sanbase.ShortUrl{} = short_url} -> {:ok, short_url}
      {:error, error} -> {:error, changeset_errors_string(error)}
    end
  end
end
