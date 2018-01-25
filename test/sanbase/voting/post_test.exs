defmodule Sanbase.Voting.PostTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Poll, Post}

  test "changeset does not allow to approve the post" do
    poll = Poll.current_poll_changeset()
    |> Repo.insert!

    user = %User{salt: User.generate_salt()}
    |> Repo.insert!

    post = %Post{user_id: user.id, poll_id: poll.id}
    |> Post.changeset(%{
      link: "http://example.com",
      title: "Awesome article!",
      approved_at: Timex.now()
    })
    |> Repo.insert!

    assert post.approved_at == nil
  end

  test "approve_changeset is updating the approved_at column" do
    changeset = %Post{}
    |> Post.approve_changeset()

    assert Timex.diff(Timex.now(), changeset.changes[:approved_at], :seconds) == 0
  end
end
