defmodule Sanbase.DiscordBot.AiReviewIssue do
  @moduledoc """
  One kind of problem seen in AI bot turns, identified by its `signature`.
  See `Sanbase.DiscordBot.AiReviewIssues`.
  """

  use Ecto.Schema

  @statuses ~w(open resolved recurred)

  schema "ai_review_issues" do
    field(:signature, :string)
    field(:flag, :string)
    field(:status, :string, default: "open")
    field(:occurrences, :integer, default: 0)
    field(:recurrences, :integer, default: 0)
    field(:first_seen_at, :naive_datetime)
    field(:last_seen_at, :naive_datetime)
    field(:resolved_at, :utc_datetime)
    field(:resolution_note, :string)

    belongs_to(:last_ai_context, Sanbase.DiscordBot.AiContext)
    belongs_to(:resolved_by, Sanbase.Accounts.User)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses(), do: @statuses
end
