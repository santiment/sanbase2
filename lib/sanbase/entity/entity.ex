defmodule Sanbase.Entity do
  @moduledoc ~s"""
  Provide unified access to all sanbase defined entities.

  Entities include:
  - Insight
  - Watchlist
  - Screener
  - Timeline Event
  - Chart Configuration

  This module provides functions for fetching lists of entities of a given type,
  ordered in a specific way. There are two orderings:
  - most recent first
  - most voted first
  """
  import Ecto.Query

  alias Sanbase.Chart
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent

  def get_most_voted(entity, opts), do: do_get_most_voted(entity, opts)

  def get_most_recent(entity, opts), do: do_get_most_recent(entity, opts)

  def deduce_entity_field(:insight), do: :post_id
  def deduce_entity_field(:watchlist), do: :watchlist_id
  def deduce_entity_field(:screener), do: :watchlist_id
  def deduce_entity_field(:timeline_event), do: :timeline_event_id
  def deduce_entity_field(:chart_configuration), do: :chart_configuration_id

  # Private functions

  defp do_get_most_recent(entity, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    public_enitiy_ids_query = public_entity_ids_query(entity)
    entity_module = deduce_entity_module(entity)

    entity_ids =
      from(
        entity in entity_module,
        select: entity.id,
        where: entity.id in subquery(public_enitiy_ids_query),
        order_by: [desc: entity.id],
        limit: ^limit,
        offset: ^offset
      )
      |> Sanbase.Repo.all()

    case entity_module.by_ids(entity_ids, []) do
      {:ok, result} -> {:ok, Enum.map(result, fn e -> %{entity => e} end)}
      {:error, error} -> {:error, error}
    end
  end

  defp do_get_most_voted(entity, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)
    entity_field = deduce_entity_field(entity)

    # We cannot just find the most voted entity as it could be
    # made private at some point after getting votes. For this reason
    # look only at entities that are public. In order to have the same
    # result for everybody the owner of a private entity does not
    # get their private entities in the ranking
    entity_module = deduce_entity_module(entity)
    public_enitiy_ids_query = public_entity_ids_query(entity)

    entity_ids =
      from(
        vote in Sanbase.Vote,
        right_join: entity in ^entity_module,
        on: field(vote, ^entity_field) == entity.id,
        where: entity.id in subquery(public_enitiy_ids_query),
        group_by: entity.id,
        select: entity.id,
        order_by: [desc: coalesce(sum(vote.count), 0), desc: entity.id],
        limit: ^limit,
        offset: ^offset
      )
      |> Sanbase.Repo.all()

    case entity_module.by_ids(entity_ids, []) do
      {:ok, result} -> {:ok, Enum.map(result, fn e -> %{entity => e} end)}
      {:error, error} -> {:error, error}
    end
  end

  defp public_entity_ids_query(:insight),
    do: Post.public_entity_ids_query(preload?: false)

  defp public_entity_ids_query(:screener),
    do: UserList.public_entity_ids_query(is_screener: true)

  defp public_entity_ids_query(:watchlist),
    do: UserList.public_entity_ids_query(is_screener: false)

  defp public_entity_ids_query(:chart_configuration),
    do: Chart.Configuration.public_entity_ids_query([])

  defp public_entity_ids_query(:timeline_event),
    do: TimelineEvent.public_entity_ids_query([])

  defp deduce_entity_module(:insight), do: Post
  defp deduce_entity_module(:watchlist), do: UserList
  defp deduce_entity_module(:screener), do: UserList
  defp deduce_entity_module(:timeline_event), do: TimelineEvent
  defp deduce_entity_module(:chart_configuration), do: Chart.Configuration
end
