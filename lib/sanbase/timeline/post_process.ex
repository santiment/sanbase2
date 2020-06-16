defmodule Sanbase.Timeline.PostProcess do
  @moduledoc """
  Module with post processing fuctions for the timeline events.
  """

  # All tags: [:by_me, :by_sanfam, :by_followed, :insight, :pulse, :alert]

  def tag(events, current_user_id \\ nil) do
    sanfamily_ids = Sanbase.Auth.Role.san_family_ids()

    followed_users_ids =
      if current_user_id do
        Sanbase.Auth.UserFollower.followed_by(current_user_id)
        |> Enum.map(& &1.id)
      else
        []
      end

    add_tag = fn tags, tag, pred ->
      if pred.(), do: tags ++ [tag], else: tags
    end

    events
    |> Enum.map(fn event ->
      []
      |> add_tag.(:by_me, fn -> current_user_id == event.user.id end)
      |> add_tag.(:by_sanfam, fn -> event.user.id in sanfamily_ids end)
      |> add_tag.(:by_followed, fn -> event.user.id in followed_users_ids end)
      |> add_tag.(:insight, fn -> event.post != nil end)
      |> add_tag.(:pulse, fn -> event.post != nil and event.post.is_pulse end)
      |> add_tag.(:alert, fn -> event.user_trigger != nil end)
      |> add_tags(event)
    end)
  end

  defp add_tags(tags, event) do
    %{event | tags: tags}
  end
end
