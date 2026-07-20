defmodule Sanbase.MajorTopics.TopicBatch do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.MajorTopics.MajorTopic

  @draft "draft"
  @published "published"
  @states [@draft, @published]

  @day "day"
  @week "week"

  @daily_only_scope "daily_only"
  @weekly_only_scope "weekly_only"
  @daily_weekly_scope "daily_weekly"
  @moderator_publication_scopes [@daily_only_scope, @daily_weekly_scope]
  @publication_scopes [@daily_only_scope, @weekly_only_scope, @daily_weekly_scope]

  def draft_state, do: @draft
  def published_state, do: @published
  def states, do: @states

  def day_granularity, do: @day
  def week_granularity, do: @week

  @doc "Publication scope for batches served only to daily views."
  @spec daily_only_scope() :: String.t()
  def daily_only_scope, do: @daily_only_scope

  @doc "Publication scope for batches served to both daily and weekly views."
  @spec daily_weekly_scope() :: String.t()
  def daily_weekly_scope, do: @daily_weekly_scope

  @doc "Publication scope for historical batches served only to weekly views."
  @spec weekly_only_scope() :: String.t()
  def weekly_only_scope, do: @weekly_only_scope

  @doc "All valid publication scopes."
  @spec publication_scopes() :: [String.t()]
  def publication_scopes, do: @publication_scopes

  @doc "Publication scopes eligible for the requested API granularity."
  @spec publication_scopes_for_granularity(String.t()) :: [String.t()]
  def publication_scopes_for_granularity(@day),
    do: [@daily_only_scope, @daily_weekly_scope]

  def publication_scopes_for_granularity(@week),
    do: [@weekly_only_scope, @daily_weekly_scope]

  schema "topic_batches" do
    field(:source, :string)
    field(:interval_text, :string)
    field(:interval_start, :date)
    field(:interval_end, :date)
    field(:version, :integer, default: 1)
    field(:type, :string)
    field(:state, :string, default: @draft)
    field(:publication_scope, :string)
    field(:published_at, :utc_datetime)
    field(:fetched_at, :utc_datetime)

    belongs_to(:published_by, User)
    has_many(:topics, MajorTopic, foreign_key: :batch_id, on_delete: :delete_all)

    timestamps()
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :source,
      :interval_text,
      :interval_start,
      :interval_end,
      :version,
      :type,
      :state,
      :fetched_at
    ])
    |> validate_required([
      :source,
      :interval_text,
      :interval_start,
      :interval_end,
      :version,
      :state,
      :fetched_at
    ])
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:source, :interval_text, :version])
  end

  @doc "Build a changeset that publishes a batch with an explicit publication scope."
  @spec publish_changeset(struct(), integer() | nil, String.t() | nil, DateTime.t()) ::
          Ecto.Changeset.t()
  def publish_changeset(batch, user_id, publication_scope, now \\ DateTime.utc_now()) do
    batch
    |> cast(
      %{
        state: @published,
        publication_scope: publication_scope,
        published_at: DateTime.truncate(now, :second),
        published_by_id: user_id
      },
      [:state, :publication_scope, :published_at, :published_by_id]
    )
    |> validate_required(:publication_scope)
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:publication_scope, @moderator_publication_scopes)
    |> check_constraint(:publication_scope, name: :topic_batches_publication_scope_valid)
    |> check_constraint(:publication_scope,
      name: :published_topic_batches_require_publication_scope
    )
  end
end
