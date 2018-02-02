defmodule Sanbase.ExAdmin.Voting.Post do
  use ExAdmin.Register

  alias Sanbase.Voting.Post

  register_resource Sanbase.Voting.Post do
    form post do
      inputs do
        input(post, :title)
        input(post, :link)
        input(post, :state, collection: [Post.approved_state(), Post.declined_state()])
        input(post, :moderation_comment)
      end
    end
  end
end
