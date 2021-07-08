defmodule SanbaseWeb.Graphql.PostgresDataloader do
  import Ecto.Query
  alias Sanbase.Model.{MarketSegment, Infrastructure}
  alias Sanbase.Repo

  def data() do
    Dataloader.KV.new(&query/2)
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

  def query(:comment_insight_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.Insight.PostComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.post_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:comment_timeline_event_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.Timeline.TimelineEventComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.timeline_event_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:comment_blockchain_address_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.BlockchainAddress.BlockchainAddressComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.blockchain_address_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:comment_proposal_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.WalletHunters.WalletHuntersProposalComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.proposal_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:comment_short_url_id, comment_ids) do
    ids = Enum.to_list(comment_ids)

    from(mapping in Sanbase.ShortUrl.ShortUrlComment,
      where: mapping.comment_id in ^ids,
      select: {mapping.comment_id, mapping.short_url_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:insights_comments_count, post_ids) do
    ids = Enum.to_list(post_ids)

    from(mapping in Sanbase.Insight.PostComment,
      where: mapping.post_id in ^ids,
      group_by: mapping.post_id,
      select: {mapping.post_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:insights_count_per_user, _user_ids) do
    {:ok, map} = Sanbase.Insight.Post.insights_count_map()
    map
  end

  def query(:timeline_events_comments_count, timeline_events_ids) do
    ids = Enum.to_list(timeline_events_ids)

    from(mapping in Sanbase.Timeline.TimelineEventComment,
      where: mapping.timeline_event_id in ^ids,
      group_by: mapping.timeline_event_id,
      select: {mapping.timeline_event_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:blockchain_addresses_comments_count, blockchain_address_ids) do
    ids = Enum.to_list(blockchain_address_ids)

    from(mapping in Sanbase.BlockchainAddress.BlockchainAddressComment,
      where: mapping.blockchain_address_id in ^ids,
      group_by: mapping.blockchain_address_id,
      select: {mapping.blockchain_address_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:short_urls_comments_count, short_url_ids) do
    ids = Enum.to_list(short_url_ids)

    from(mapping in Sanbase.ShortUrl.ShortUrlComment,
      where: mapping.short_url_id in ^ids,
      group_by: mapping.short_url_id,
      select: {mapping.short_url_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

  def query(:wallet_hunters_proposals_comments_count, proposal_ids) do
    ids = Enum.to_list(proposal_ids)

    from(mapping in Sanbase.WalletHunters.WalletHuntersProposalComment,
      where: mapping.proposal_id in ^ids,
      group_by: mapping.proposal_id,
      select: {mapping.proposal_id, fragment("COUNT(*)")}
    )
    |> Repo.all()
    |> Map.new()
  end

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
end
