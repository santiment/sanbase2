defmodule Sanbase.Tag.Preloader do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Insight.Post

  def order_tags([]), do: []
  def order_tags(%Post{} = post), do: order_tags([post]) |> hd()

  def order_tags([%Post{} | _] = structs) do
    structs = Repo.preload(structs, [:tags])
    post_id_to_ordered_tag_ids = post_id_to_ordered_tag_ids(structs)

    Enum.map(structs, fn
      %Post{tags: []} = post ->
        post

      %Post{tags: tags} = post ->
        tags_order = Map.get(post_id_to_ordered_tag_ids, post.id)
        tags = Enum.map(tags_order, fn tag_id -> Enum.find(tags, &(&1.id == tag_id)) end)

        %Post{post | tags: tags}
    end)
  end

  # Get a map where the key is the post_id and the value is the list of tags in
  # the proper order
  defp post_id_to_ordered_tag_ids(structs) do
    post_ids = structs |> Enum.map(& &1.id)

    from(pt in "posts_tags",
      where: pt.post_id in ^post_ids,
      select: {pt.post_id, pt.tag_id, pt.id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {post_id, tag_id, pair_id}, acc ->
      elem = {tag_id, pair_id}
      Map.update(acc, post_id, [elem], &[elem | &1])
    end)
    |> Enum.into(%{}, fn {post_id, tags} ->
      tags = Enum.sort_by(tags, &elem(&1, 1)) |> Enum.map(&elem(&1, 0))
      {post_id, tags}
    end)
  end
end
