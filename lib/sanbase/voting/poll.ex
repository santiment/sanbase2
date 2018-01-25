defmodule Sanbase.Voting.Poll do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  use Timex.Ecto.Timestamps

  alias Sanbase.Voting.{Poll, Post}
  alias Sanbase.Repo

  @poll_length_days 7

  schema "polls" do
    field(:start_at, Timex.Ecto.DateTime)
    field(:end_at, Timex.Ecto.DateTime)

    has_many(:posts, Post)

    timestamps()
  end

  def changeset(%Poll{} = poll, attrs \\ %{}) do
    poll
    |> cast(attrs, [:start_at, :end_at])
    |> validate_required([:start_at, :end_at])
    |> unique_constraint(:start_at)
  end

  def find_or_insert_current_poll!() do
    case current_poll() do
      nil -> current_poll_changeset() |> Repo.insert!()
      poll -> poll
    end
  end

  def current_poll do
    Poll
    |> where([p], p.start_at <= ^Timex.now() and p.end_at > ^Timex.now())
    |> Repo.one()
  end

  def last_poll_end_at do
    case current_poll() do
      nil -> Timex.beginning_of_week(Timex.now())
      poll -> poll.end_at
    end
  end

  def current_poll_changeset do
    %Poll{}
    |> changeset(%{
      start_at: last_poll_end_at(),
      end_at: Timex.shift(last_poll_end_at(), days: @poll_length_days)
    })
  end
end
