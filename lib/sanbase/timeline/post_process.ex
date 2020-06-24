defmodule Sanbase.Timeline.PostProcess do
  @moduledoc """
  Module with post processing fuctions for the timeline events.
  """

  @doc """
  Tag timeline events by owner and by type.
  All used tags: [:by_me, :by_sanfam, :by_followed, :insight, :pulse, :alert]
  """

  def tag(events, current_user_id \\ nil) do
    sanfamily_ids = Sanbase.Auth.Role.san_family_ids()

    followed_users_ids =
      if current_user_id do
        Sanbase.Auth.UserFollower.followed_by(current_user_id)
        |> Enum.map(& &1.id)
      else
        []
      end

    add_tag = fn
      tags, _tag, false -> tags
      tags, tag, true -> [tag | tags]
    end

    events
    |> Enum.map(fn event ->
      []
      |> add_tag.(:by_me, current_user_id == event.user.id)
      |> add_tag.(:by_sanfam, event.user.id in sanfamily_ids)
      |> add_tag.(:by_followed, event.user.id in followed_users_ids)
      |> add_tag.(:insight, event.post != nil)
      |> add_tag.(:pulse, event.post != nil and event.post.is_pulse)
      |> add_tag.(:alert, event.user_trigger != nil)
      |> add_tags(event)
    end)
  end

  defp add_tags(tags, event) do
    %{event | tags: Enum.reverse(tags)}
  end
end
