defmodule Sanbase.UserList.Monitor do
  @moduledoc """
  Watchlist can be monitored - this means the creator will receive an email if any
  of the assets in the watchlist is present in the insights' tags created by SAN family
  or by followed authors.
  """

  require Logger
  import Ecto.Query

  alias Sanbase.UserList
  alias Sanbase.Auth.{User, UserRole, Role}
  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  def run() do
    User.users_with_monitored_watchlist_and_email()
    |> Enum.each(&run_for_user/1)
  end

  def run_for_user(user) do
    now = Timex.now()
    week_ago = week_ago(now)

    watchlists = monitored_watchlists_for(user)

    insights_to_send(user, watchlists, week_ago)
    |> try_sending_email(watchlists, user, week_ago, now)
  end

  def try_sending_email([], _, _, _, _), do: :ok

  def try_sending_email(insights, watchlists, user, week_ago, now) do
    create_email_params(watchlists, insights, week_ago, now)
    |> send_email(user)
  end

  def send_email(%{watchlists: watchlists, insights: insights} = send_params, user)
      when is_list(watchlists) and is_list(insights) and length(watchlists) > 0 and
             length(insights) > 0 do
    send_result =
      Sanbase.MandrillApi.send("Monitoring watchlist", user.email, send_params, %{
        merge_language: "handlebars"
      })

    Logger.info("Inspect watchlist monitor digest.
      sent to email: [#{user.email}]
      send_params: [#{inspect(send_params)}]
      send_result: #{inspect(send_result)}")
  end

  def send_email(send_params, user) do
    Logger.warn(
      "Failed sending watchlist monitor digest to user: #{inspect(user)}. Send params: #{
        inspect(send_params)
      }"
    )

    :ok
  end

  def create_email_params(watchlists, insights, week_ago, now) do
    %{
      dates: format_dates(week_ago, now),
      watchlists:
        Enum.map(watchlists, &format_watchlist(&1, week_ago, now)) |> Enum.reject(&is_nil/1),
      insights: Enum.map(insights, &format_insight(&1))
    }
  end

  @doc """
  Take all published and approved insights from the last week from
  authors followed by the user OR san family members. Filter only the insights
  that contain tags for projects that are in some of the user's monitored watchlists.
  """

  def insights_to_send(_user, [], _), do: []

  def insights_to_send(user, watchlists, week_ago) do
    week_ago
    |> Post.public_insights_after()
    |> insights_by_followed_users_or_sanfamily(user.id)
    |> insights_with_asset_in_monitored_watchlist(watchlists)
  end

  @doc """
  A tag for a watchlist is ine of the contained projects' slug, ticker or name.
  Returns all tags for given list of watchlists removing duplicates
  """
  def watchlists_tags(watchlists) do
    watchlists
    |> Enum.flat_map(fn watchlist ->
      watchlist.list_items
      |> Enum.flat_map(&[&1.project.slug, &1.project.ticker, &1.project.name])
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  def monitored_watchlists_for(%User{id: user_id}) do
    from(ul in UserList,
      where: ul.user_id == ^user_id and ul.is_monitored == true,
      preload: [list_items: [:project]]
    )
    |> Repo.all()
  end

  defp format_dates(week_ago, now) do
    "#{Timex.format!(week_ago, "%B %d", :strftime)} - #{Timex.format!(now, "%B %d", :strftime)}"
  end

  defp format_watchlist(%UserList{id: id, name: name, list_items: list_items}, week_ago, now) do
    slugs =
      list_items
      |> Enum.map(& &1.project.slug)

    with {:ok, measurement_slugs_map} <- Sanbase.Influxdb.Measurement.names_from_slugs(slugs),
         {:ok, result} <-
           Sanbase.Prices.Store.fetch_volume_mcap_multiple_measurements_no_cache(
             measurement_slugs_map,
             week_ago,
             now
           ) do
      combined_mcap = result |> Enum.reduce(0, fn {_, _, mcap, _}, acc -> acc + mcap end)
      name_query = URI.encode_query(%{"name" => name})

      %{
        "watchlist-title" => name,
        "watchlist-marketcap" => "$ #{format_number(combined_mcap)}",
        "watchlist-link" => "https://app.santiment.net/assets/list?#{name_query}@#{id}"
      }
    else
      error ->
        Logger.error(
          "error computing combined marketcap for slugs: #{inspect(slugs)}. Reason: #{
            inspect(error)
          }"
        )

        nil
    end
  end

  defp format_insight(%Post{
         id: id,
         title: title,
         user: %User{username: author},
         published_at: published_at,
         tags: tags
       }) do
    tags = tags |> Enum.map(fn %{name: name} -> String.downcase(name) end)

    %{
      "insight-title" => title,
      "insight-author" => author,
      "insight-date" => Timex.format!(published_at, "%B %d, %Y", :strftime),
      "insight-link" => "https://insights.santiment.net/read/#{id}",
      "tags" => tags
    }
  end

  defp format_number(number) do
    cond do
      number / 1_000_000_000 > 1 ->
        (number / 1_000_000_000) |> Float.round(2) |> Float.to_string() |> Kernel.<>("B")

      number / 1_000_000 > 1 ->
        (number / 1_000_000) |> Float.round(2) |> Float.to_string() |> Kernel.<>("M")

      true ->
        number |> Integer.to_string()
    end
  end

  defp insights_by_followed_users_or_sanfamily(insights, user_id) do
    followed_users = Sanbase.Following.UserFollower.followed_by(user_id)
    san_family_ids = san_family_ids()

    insights
    |> Enum.filter(fn %Post{user_id: author_id} ->
      author_id != user_id and
        (author_id in san_family_ids or author_id in followed_users)
    end)
  end

  defp insights_with_asset_in_monitored_watchlist(insights, watchlists) do
    watchlists_tags = watchlists_tags(watchlists)

    insights
    |> Enum.filter(fn %Post{tags: tags} ->
      tags
      |> Enum.any?(fn tag ->
        tag.name in watchlists_tags
      end)
    end)
  end

  defp week_ago(now), do: Timex.shift(now, days: -7)

  defp san_family_ids() do
    from(ur in UserRole,
      where: ur.role_id == ^Role.san_family_role_id(),
      select: ur.user_id
    )
    |> Repo.all()
  end
end
