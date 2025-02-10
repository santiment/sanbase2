defmodule Sanbase.Timeline.Query do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.UserList

  # Events with public entities and current user private events
  def events_with_event_type(query, types) do
    from(
      event in query,
      where: event.event_type in ^types
    )
  end

  def events_with_public_entities_query(query) do
    from(
      event in query,
      left_join: ut in UserTrigger,
      on: event.user_trigger_id == ut.id,
      left_join: ul in UserList,
      on: event.user_list_id == ul.id,
      left_join: post in Sanbase.Insight.Post,
      on: event.post_id == post.id,
      where:
        (not is_nil(event.post_id) and post.ready_state == "published" and
           post.state == "approved") or
          ul.is_public == true or
          fragment("?.trigger->>'is_public' = 'true'", ut)
    )
  end

  def events_with_public_entities_query(query, user_id) do
    from(
      event in query,
      left_join: ut in UserTrigger,
      on: event.user_trigger_id == ut.id,
      left_join: ul in UserList,
      on: event.user_list_id == ul.id,
      where:
        event.user_id == ^user_id or
          (event.user_id != ^user_id and
             (not is_nil(event.post_id) or
                ul.is_public == true or
                fragment("?.trigger->>'is_public' = 'true'", ut)))
    )
  end

  def events_by_sanfamily_or_followed_users_or_own_query(query, user_id) do
    sanclan_or_followed_users_or_own_ids =
      user_id
      |> UserFollower.followed_by_with_notifications_enabled()
      |> Enum.map(& &1.id)
      |> Enum.concat(Role.san_family_ids())
      |> Enum.concat([user_id])
      |> Enum.dedup()

    from(
      event in query,
      where: event.user_id in ^sanclan_or_followed_users_or_own_ids
    )
  end

  def events_by_sanfamily_query(query) do
    sanfamily_ids = Sanbase.Accounts.Role.san_family_ids()

    from(
      event in query,
      where: event.user_id in ^sanfamily_ids
    )
  end

  def events_by_followed_users_query(query, user_id) do
    followed_users_ids =
      user_id
      |> UserFollower.followed_by_with_notifications_enabled()
      |> Enum.map(& &1.id)

    from(
      event in query,
      where: event.user_id in ^followed_users_ids
    )
  end

  def events_by_current_user_query(query, user_id) do
    from(
      event in query,
      where: event.user_id == ^user_id
    )
  end
end
