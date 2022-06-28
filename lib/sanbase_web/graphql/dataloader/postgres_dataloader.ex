defmodule SanbaseWeb.Graphql.PostgresDataloader do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Comment
  alias Sanbase.Model.{MarketSegment, Infrastructure}

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:insight_vote_stats, data), do: get_votes_stats(:insight, :post_id, data)
  def query(:insight_voted_at, data), do: get_voted_at(:insight, :post_id, data)

  def query(:watchlist_vote_stats, data), do: get_votes_stats(:watchlist, :watchlist_id, data)
  def query(:watchlist_voted_at, data), do: get_voted_at(:watchlist, :watchlist_id, data)

  def query(:dashboard_vote_stats, data), do: get_votes_stats(:dashboard, :dashboard_id, data)
  def query(:dashboard_voted_at, data), do: get_voted_at(:dashboard, :dashboard_id, data)

  def query(:timeline_event_vote_stats, data),
    do: get_votes_stats(:timeline_event, :timeline_event_id, data)

  def query(:timeline_event_voted_at, data),
    do: get_voted_at(:timeline_event, :timeline_event_id, data)

  def query(:chart_configuration_vote_stats, data),
    do: get_votes_stats(:chart_configuration, :chart_configuration_id, data)

  def query(:chart_configuration_voted_at, data),
    do: get_voted_at(:chart_configuration, :chart_configuration_id, data)

  def query(:user_trigger_vote_stats, data),
    do: get_votes_stats(:user_trigger, :user_trigger_id, data)

  def query(:user_trigger_voted_at, data),
    do: get_voted_at(:user_trigger, :user_trigger_id, data)

  def query(:users_by_id, user_ids) do
    user_ids = Enum.to_list(user_ids)

    {:ok, users} = Sanbase.Accounts.User.by_id(user_ids)
    Map.new(users, &{&1.id, &1})
  end

  def query(:market_segment, market_segment_ids) do
    market_segment_ids = Enum.to_list(market_segment_ids)

    from(ms in MarketSegment,
      where: ms.id in ^market_segment_ids
    )
    |> Repo.all()
    |> Enum.map(fn %MarketSegment{id: id, name: name} -> {id, name} end)
    |> Map.new()
  end

  def query(:infrastructure, infrastructure_ids) do
    infrastructure_ids = Enum.to_list(infrastructure_ids)

    Infrastructure.by_ids(infrastructure_ids)
    |> Map.new(fn %Infrastructure{id: id, code: code} -> {id, code} end)
  end

  def query(:traded_on_exchanges, slugs_mapset) do
    slugs = Enum.to_list(slugs_mapset)

    Sanbase.Market.exchanges_per_slug(slugs)
    |> Map.new()
  end

  def query(:traded_on_exchanges_count, slugs_mapset) do
    slugs = Enum.to_list(slugs_mapset)

    Sanbase.Market.exchanges_count_per_slug(slugs)
    |> Map.new()
  end

  def query(:insights_count_per_user, _user_ids) do
    {:ok, map} = Sanbase.Insight.Post.insights_count_map()
    map
  end

  # Comment entity id functions
  def query(:comment_insight_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.PostComment, :post_id)
  end

  def query(:comment_watchlist_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.WatchlistComment, :watchlist_id)
  end

  def query(:comment_dashboard_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.DashboardComment, :dashboard_id)
  end

  def query(:comment_chart_configuration_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.ChartConfigurationComment, :chart_configuration_id)
  end

  def query(:comment_timeline_event_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.TimelineEventComment, :timeline_event_id)
  end

  def query(:comment_blockchain_address_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.BlockchainAddressComment, :blockchain_address_id)
  end

  def query(:comment_wallet_hunter_proposal_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.WalletHuntersProposalComment, :proposal_id)
  end

  def query(:comment_short_url_id, ids_mapset) do
    get_comment_entity_id(ids_mapset, Comment.ShortUrlComment, :short_url_id)
  end

  # End comments entity id

  # Comments count functions
  def query(:insights_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.PostComment, :post_id)
  end

  def query(:timeline_events_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.TimelineEventComment, :timeline_event_id)
  end

  def query(:blockchain_addresses_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.BlockchainAddressComment, :blockchain_address_id)
  end

  def query(:short_urls_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.ShortUrlComment, :short_url_id)
  end

  def query(:wallet_hunters_proposals_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.WalletHuntersProposalComment, :proposal_id)
  end

  def query(:watchlist_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.WatchlistComment, :watchlist_id)
  end

  def query(:dashboard_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.DashboardComment, :dashboard_id)
  end

  def query(:chart_configuration_comments_count, ids_mapset) do
    get_comments_count(ids_mapset, Comment.ChartConfigurationComment, :chart_configuration_id)
  end

  # End comments count

  def query(:current_user_address_details, data) do
    Enum.group_by(data, &{&1.user_id, &1.infrastructure}, & &1.address)
    |> Enum.map(fn {{user_id, infrastructure}, addresses} ->
      query =
        from(
          baup in Sanbase.BlockchainAddress.BlockchainAddressUserPair,
          preload: [:labels],
          inner_join: ba in Sanbase.BlockchainAddress,
          on: baup.blockchain_address_id == ba.id and ba.address in ^addresses,
          left_join: li in Sanbase.UserList.ListItem,
          on: li.blockchain_address_user_pair_id == baup.id,
          left_join: ul in Sanbase.UserList,
          on: ul.id == li.user_list_id,
          where: baup.user_id == ^user_id and ul.user_id == ^user_id,
          select: %{
            blockchain_address_user_pair: baup,
            address: ba.address,
            watchlist: %{id: ul.id, name: ul.name, slug: ul.slug}
          }
        )

      Sanbase.Repo.all(query)
      |> combine_current_user_address_details(user_id, infrastructure)
    end)
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  def query(:project_by_slug, slugs) do
    slugs
    |> Enum.to_list()
    |> Sanbase.Model.Project.List.by_slugs()
    |> Enum.into(%{}, fn %{slug: slug} = project -> {slug, project} end)
  end

  # Private functions

  def get_comments_count(ids_mapset, module, field) do
    ids = Enum.to_list(ids_mapset)

    from(mapping in module,
      where: field(mapping, ^field) in ^ids,
      group_by: field(mapping, ^field),
      select: {field(mapping, ^field), fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_comment_entity_id(ids_mapset, module, field) do
    ids = Enum.to_list(ids_mapset)

    from(mapping in module,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, field(mapping, ^field)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp combine_current_user_address_details(list, user_id, infrastructure) do
    list
    |> Enum.reduce(%{}, fn row, acc ->
      key = %{user_id: user_id, address: row.address, infrastructure: infrastructure}

      # If the row has a watchlist create a list with it, otherwise make it
      # an empty list. This way this watchlist can be prepened to the list of
      # watchlists without any conditionals
      watchlist = if row.watchlist.id, do: [row.watchlist], else: []

      labels =
        Enum.map(row.blockchain_address_user_pair.labels, &%{name: &1.name, origin: "user"})

      elem =
        row
        |> Map.merge(%{
          notes: row.blockchain_address_user_pair.notes,
          watchlists: watchlist,
          labels: labels
        })

      Map.update(acc, key, elem, fn user_address_pair ->
        Map.update!(user_address_pair, :watchlists, &(watchlist ++ &1))
      end)
    end)
    |> post_process_transform()
  end

  # Do this in order to have a specific order so it can be tested easier
  defp post_process_transform(data) do
    data
    |> Enum.into(%{}, fn {key, value} ->
      sort_fun = fn list -> Enum.sort_by(list, & &1.id, :desc) end
      value = Map.update!(value, :watchlists, sort_fun)
      {key, value}
    end)
  end

  defp get_votes_stats(entity, entity_key, data) do
    user_group = Enum.group_by(data, & &1[:user_id], & &1[entity_key])

    Enum.map(user_group, fn {user_id, entity_ids} ->
      Sanbase.Vote.vote_stats(entity, entity_ids, user_id)
      |> Map.new(fn %{entity_id: id} = map -> {%{entity_key => id, user_id: user_id}, map} end)
    end)
    |> Enum.reduce(&Map.merge(&1, &2))
  end

  defp get_voted_at(entity, entity_key, data) do
    user_group = Enum.group_by(data, & &1[:user_id], & &1[entity_key])

    Enum.map(user_group, fn {user_id, entity_ids} ->
      Sanbase.Vote.voted_at(entity, entity_ids, user_id)
      |> Map.new(fn %{entity_id: id} = map -> {%{entity_key => id, user_id: user_id}, map} end)
    end)
    |> Enum.reduce(&Map.merge(&1, &2))
  end
end
