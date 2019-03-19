defmodule Sanbase.ExAdmin.Insight.Post do
  use ExAdmin.Register

  alias Sanbase.Insight.Post

  register_resource Sanbase.Insight.Post do
    create_changeset(:create_changeset)
    update_changeset(:update_changeset)
    action_items(only: [:show, :edit, :delete])

    index do
      column(:id)
      column(:title)
      column(:is_featured, &is_featured(&1))
      column(:state)
      column(:ready_state)
      column(:moderation_comment)
      column(:user, link: true)
    end

    show _post do
      attributes_table do
        row(:id)
        row(:is_featured, &is_featured(&1))
        row(:title)
        row(:short_desc)
        row(:text)
        row(:state)
        row(:ready_state)
        row(:moderation_comment)
        row(:link)
        row(:discourse_topic_url)
        row(:user, link: true)
      end
    end

    form post do
      inputs do
        input(
          post,
          :is_featured,
          collection: ~w[true false]
        )

        input(post, :state, collection: [Post.approved_state(), Post.declined_state()])
        input(post, :moderation_comment)
      end
    end

    controller do
      after_filter(:set_featured, only: [:update])
    end
  end

  defp is_featured(%Post{} = ut) do
    ut = Sanbase.Repo.preload(ut, [:featured_item])
    (ut.featured_item != nil) |> Atom.to_string()
  end

  def set_featured(conn, params, resource, :update) do
    is_featured = params.post.is_featured |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(resource, is_featured)
    {conn, params, resource}
  end
end
