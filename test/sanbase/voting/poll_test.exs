defmodule Sanbase.Voting.PollTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Voting.Poll

  test "current_poll returns nil if there is no current poll" do
    assert Poll.current_poll() == nil
  end

  test "current_poll returns nil if there is an old poll" do
    %Poll{}
    |> Poll.changeset(%{
      start_at: Timex.shift(Timex.now(), months: 2),
      end_at: Timex.shift(Timex.now(), months: 1)
    })

    assert Poll.current_poll() == nil
  end

  test "current_poll returns the current poll if there is one" do
    Poll.current_poll_changeset()
    |> Repo.insert!

    assert Poll.current_poll() != nil
  end

  test "last_poll_end_at returns the beginning of the week if there are no polls" do
    assert Poll.last_poll_end_at() == Timex.beginning_of_week(Timex.now())
  end

  test "find_or_insert_current_poll! creates a new poll if there is none" do
    assert Poll.find_or_insert_current_poll!() != nil
  end
end
