defmodule Sanbase.Timeline.PostProcess do
  @moduledoc """
  Module with post processing fuctions for the timeline events.
  """

  @doc """
  Tag timeline events by owner and by type.
  All used tags: [:own, :sanfam, :followed, :insight, :pulse, :alert]
  """

  def tag(events, current_user_id \\ nil) do
    sanfamily_ids = Sanbase.Accounts.Role.san_family_ids()

    Enum.map(events, fn event ->
      []
      |> add_tag(:own, current_user_id == event.user.id)
      |> add_tag(:sanfam, event.user.id in sanfamily_ids)
      |> add_tag(:followed, event.user.id in followed_users_ids(current_user_id))
      |> add_tag(:insight, event.post != nil)
      |> add_tag(:pulse, event.post != nil and event.post.is_pulse)
      |> add_tag(:alert, event.user_trigger != nil)
      |> add_tags(event)
    end)
  end

  defp followed_users_ids(nil = _follower_user_id), do: []

  defp followed_users_ids(follower_user_id) do
    follower_user_id
    |> Sanbase.Accounts.UserFollower.followed_by()
    |> Enum.map(& &1.id)
  end

  defp add_tag(tags, _tag, false), do: tags
  defp add_tag(tags, tag, true), do: [tag | tags]

  defp add_tags(tags, event) do
    %{event | tags: Enum.reverse(tags)}
  end
end
