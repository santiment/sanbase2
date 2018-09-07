defmodule Sanbase.Voting.PostTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post}

  test "create_changeset does not allow to approve the post" do
    poll =
      Poll.current_poll_changeset()
      |> Repo.insert!()

    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    post =
      %Post{user_id: user.id, poll_id: poll.id}
      |> Post.create_changeset(%{
        text: "Some text",
        title: "Awesome article!",
        state: Post.approved_state()
      })
      |> Repo.insert!()

    assert post.state == nil
  end

  test "changes the owner to the fallback user" do
    poll = Poll.find_or_insert_current_poll!()
    insights_user = insert(:insights_fallback_user)
    user = insert(:user)
    post = insert(:post, poll_id: poll.id, user_id: user.id)

    Post.change_owner_to_anonymous(user.id)

    updated_post = Post |> Repo.get(post.id)

    assert updated_post.user_id == insights_user.id
  end
end
