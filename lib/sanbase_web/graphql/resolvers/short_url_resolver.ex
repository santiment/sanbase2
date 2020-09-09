defmodule SanbaseWeb.Graphql.Resolvers.ShortUrlResolver do
  require Logger
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_to_str: 1]

  def create_short_url(_root, %{full_url: full_url}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    do_create_short_url(full_url, current_user.id)
  end

  def create_short_url(_root, %{full_url: full_url}, _resolution) do
    do_create_short_url(full_url, nil)
  end

  def get_full_url(_root, %{short_url: short_url}, _resolution) do
    case Sanbase.ShortUrl.get(short_url) do
      nil -> {:error, "Short url #{short_url} does not exist."}
      %Sanbase.ShortUrl{full_url: full_url} -> {:ok, full_url}
    end
  end

  # Private functions
  defp do_create_short_url(full_url, user_id) do
    case Sanbase.ShortUrl.create(%{full_url: full_url, user_id: user_id}) do
      {:ok, %Sanbase.ShortUrl{short_url: short_url}} -> {:ok, short_url}
      {:error, error} -> {:error, changeset_errors_to_str(error)}
    end
  end
end
