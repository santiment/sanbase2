defmodule Sanbase.ExAdmin.FeaturedItem do
  use ExAdmin.Register

  alias Sanbase.FeaturedItem

  register_resource Sanbase.FeaturedItem do
    action_items(only: [:show, :edit, :delete])

    index do
      column(:id)
      column(:post, &render_post/1, link: true)
      column(:user_trigger, &render_user_trigger/1, link: true)
      column(:user_list, &render_user_list/1, link: true)
    end
  end

  def render_post(%FeaturedItem{post: nil}), do: nil
  def render_post(%FeaturedItem{post: post}), do: post.title |> shorten()

  def render_user_trigger(%FeaturedItem{user_trigger: nil}), do: nil

  def render_user_trigger(%FeaturedItem{user_trigger: ut}),
    do: ut.trigger.title |> shorten()

  def render_user_list(%FeaturedItem{user_list: nil}), do: nil
  def render_user_list(%FeaturedItem{user_list: ul}), do: ul.name |> shorten

  defp shorten(str) when is_binary(str) do
    case String.length(str) do
      len when len > 20 ->
        (str |> String.slice(0..30)) <> "..."

      _ ->
        str
    end
  end
end
