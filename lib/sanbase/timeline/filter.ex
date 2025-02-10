defmodule Sanbase.Timeline.Filter do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Insight.Post
  alias Sanbase.Repo
  alias Sanbase.Timeline.Query
  alias Sanbase.UserList

  def filter_by_query(query, filter_by) do
    filter_by_type_query(query, filter_by)
  end

  def filter_by_query(query, filter_by, user_id) do
    query
    |> filter_by_not_seen(filter_by, user_id)
    |> filter_by_author_query(filter_by, user_id)
    |> filter_by_watchlists_query(filter_by)
    |> filter_by_assets_query(filter_by, user_id)
    |> filter_by_type_query(filter_by)
  end

  defp filter_by_not_seen(query, %{only_not_seen: true}, user_id) do
    event_id = Sanbase.Timeline.SeenEvent.last_seen_for_user(user_id)
    filter_by_last_seen_event(query, %{last_seen_event_id: event_id})
  end

  defp filter_by_not_seen(query, _, _), do: query

  defp filter_by_last_seen_event(query, %{last_seen_event_id: last_seen_event_id}) when last_seen_event_id != nil do
    from(event in query, where: event.id > ^last_seen_event_id)
  end

  defp filter_by_last_seen_event(query, _), do: query

  defp filter_by_type_query(query, %{type: :insight}) do
    from(event in query, join: p in assoc(event, :post), where: not p.is_pulse)
  end

  defp filter_by_type_query(query, %{type: :pulse}) do
    from(event in query, join: p in assoc(event, :post), where: p.is_pulse)
  end

  defp filter_by_type_query(query, %{type: :alert}) do
    from(event in query, join: p in assoc(event, :user_trigger))
  end

  defp filter_by_type_query(query, _), do: query

  defp filter_by_author_query(query, %{author: :all}, user_id) do
    Query.events_by_sanfamily_or_followed_users_or_own_query(query, user_id)
  end

  defp filter_by_author_query(query, %{author: :sanfam}, _) do
    Query.events_by_sanfamily_query(query)
  end

  defp filter_by_author_query(query, %{author: :followed}, user_id) do
    Query.events_by_followed_users_query(query, user_id)
  end

  defp filter_by_author_query(query, %{author: :own}, user_id) do
    Query.events_by_current_user_query(query, user_id)
  end

  defp filter_by_author_query(query, _, user_id) do
    Query.events_by_sanfamily_or_followed_users_or_own_query(query, user_id)
  end

  defp filter_by_watchlists_query(query, %{watchlists: watchlists}) when is_list(watchlists) and length(watchlists) > 0 do
    from(event in query, where: event.user_list_id in ^watchlists)
  end

  defp filter_by_watchlists_query(query, _), do: query

  defp filter_by_assets_query(query, %{assets: assets} = filter_by, user_id)
       when is_list(assets) and length(assets) > 0 do
    {slugs, tickers} = get_slugs_and_tickers_by_asset_list(assets)
    watchlist_ids = get_watchlist_ids_by_asset_list(assets, filter_by, user_id)
    insight_ids = get_insight_ids_by_asset_list({slugs, tickers}, filter_by, user_id)
    trigger_ids = get_trigger_ids_by_asset_list({slugs, tickers}, filter_by, user_id)

    from(event in query,
      where:
        event.user_list_id in ^watchlist_ids or
          event.post_id in ^insight_ids or
          event.user_trigger_id in ^trigger_ids
    )
  end

  defp filter_by_assets_query(query, _, _), do: query

  defp get_watchlist_ids_by_asset_list(assets, filter_by, user_id) do
    from(
      entity in UserList,
      join: li in assoc(entity, :list_items),
      where: li.project_id in ^assets,
      select: entity.id
    )
    |> filter_by_author_query(filter_by, user_id)
    |> Repo.all()
  end

  defp get_slugs_and_tickers_by_asset_list(assets) do
    project_slugs_and_tickers = Repo.all(from(p in Sanbase.Project, where: p.id in ^assets, select: [p.slug, p.ticker]))

    slugs = Enum.map(project_slugs_and_tickers, fn [slug, _] -> slug end)
    tickers = Enum.map(project_slugs_and_tickers, fn [_, ticker] -> ticker end)

    {slugs, tickers}
  end

  defp get_insight_ids_by_asset_list({slugs, tickers}, filter_by, user_id) do
    tickers_lc = Enum.map(tickers, &String.downcase/1)
    tickers_uc = Enum.map(tickers, &String.upcase/1)

    from(
      entity in Post,
      join: t in assoc(entity, :tags),
      where: t.name in ^slugs or t.name in ^tickers_uc or t.name in ^tickers_lc,
      select: entity.id
    )
    |> filter_by_author_query(filter_by, user_id)
    |> Repo.all()
  end

  defp get_trigger_ids_by_asset_list({slugs, tickers}, filter_by, user_id) do
    triggers =
      from(ut in UserTrigger, select: [ut.id, fragment("trigger->'settings'->'target'")])
      |> filter_by_author_query(filter_by, user_id)
      |> Repo.all()

    triggers
    |> Enum.filter(fn [_id, target] -> filter_by_trigger_target(target, {slugs, tickers}) end)
    |> Enum.map(fn [id, _] -> id end)
  end

  defp filter_by_trigger_target(%{"slug" => slug}, {slugs, _tickers}) when is_binary(slug), do: slug in slugs

  defp filter_by_trigger_target(%{"slug" => target_slugs}, {slugs, _tickers}) when is_binary(target_slugs) do
    has_intersection?(target_slugs, slugs)
  end

  defp filter_by_trigger_target(%{"word" => word}, {slugs, tickers}) when is_binary(word) do
    word in slugs or word in tickers or String.upcase(word) in tickers
  end

  defp filter_by_trigger_target(%{"word" => words}, {slugs, tickers}) when is_list(words) do
    tickers_lc = Enum.map(tickers, &String.downcase/1)
    tickers_uc = Enum.map(tickers, &String.upcase/1)

    has_intersection?(words, slugs) or has_intersection?(words, tickers_lc) or
      has_intersection?(words, tickers_uc)
  end

  defp filter_by_trigger_target(_, _), do: false

  defp has_intersection?(list1, list2) do
    list1 |> MapSet.new() |> MapSet.intersection(MapSet.new(list2)) |> MapSet.size() > 0
  end
end
