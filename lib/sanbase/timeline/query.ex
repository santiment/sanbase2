defmodule Sanbase.Timeline.Query do
  import Ecto.Query

  alias Sanbase.Auth.{UserFollower, Role}
  alias Sanbase.UserList
  alias Sanbase.Signal.UserTrigger

  # Events with public entities and current user private events
  def events_with_public_entities_query(query) do
    from(
      event in query,
      left_join: ut in UserTrigger,
      on: event.user_trigger_id == ut.id,
      left_join: ul in UserList,
      on: event.user_list_id == ul.id,
      where:
        not is_nil(event.post_id) or
          ul.is_public == true or
          fragment("trigger->>'is_public' = 'true'")
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
                fragment("trigger->>'is_public' = 'true'")))
    )
  end

  def events_by_sanfamily_or_followed_users_or_own_query(query, user_id) do
    sanclan_or_followed_users_or_own_ids =
      UserFollower.followed_by(user_id)
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
    sanfamily_ids = Sanbase.Auth.Role.san_family_ids()

    from(
      event in query,
      where: event.user_id in ^sanfamily_ids
    )
  end

  def events_by_followed_users_query(query, user_id) do
    followed_users_ids =
      UserFollower.followed_by(user_id)
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
