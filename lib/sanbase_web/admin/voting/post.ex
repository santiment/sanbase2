defmodule Sanbase.ExAdmin.Voting.Post do
  use ExAdmin.Register

  alias Sanbase.Voting.Post

  register_resource Sanbase.Voting.Post do
    create_changeset(:create_changeset)
    update_changeset(:update_changeset)
    action_items(only: [:show, :edit, :delete])

    form post do
      inputs do
        input(post, :title)
        input(post, :short_desc)
        input(post, :link)
        input(post, :text)
        input(post, :state, collection: [Post.approved_state(), Post.declined_state()])
        input(post, :moderation_comment)
      end
    end
  end
end
