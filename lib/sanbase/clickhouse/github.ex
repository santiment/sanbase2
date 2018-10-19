defmodule Sanbase.Clickhouse.Github do
  @moduledoc ~s"""
  Uses ClickHouse to work with ETH transfers.
  """

  @type t :: %__MODULE__{
          datetime: %DateTime{},
          owner: String.t(),
          repo: String.t(),
          actor: String.t(),
          event: String.t()
        }

  use Ecto.Schema

  require Logger
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @ignored_events [
    "IssueCommentEvent",
    "IssuesEvent",
    "PullRequestReviewCommentEvent",
    "ForkEvent"
  ]
  @table "github"

  @primary_key false
  @timestamps_opts updated_at: false
  schema @table do
    field(:datetime, :utc_datetime, source: :dt, primary_key: true)
    field(:repo, :string, primary_key: true)
    field(:event, :string, primary_key: true)
    field(:owner, :string)
    field(:actor, :string)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Cannot change github ClickHouse table!"
  end

  @doc ~s"""

  """
  @spec activity(String.t(), %DateTime{}, %DateTime{}, String.t()) ::
          {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def activity(nil, _, _, _), do: []

  def activity(organization, from, to, interval) do
    interval_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    {query, args} = activity_query(organization, from, to, interval_sec)

    ClickhouseRepo.query_transform(query, args, fn [datetime, events_count] ->
      %{
        datetime: datetime |> Sanbase.DateTimeUtils.from_erl!(),
        activity: events_count
      }
    end)
  end

  defp activity_query(organization, from_datetime, to_datetime, interval) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)
    span = div(to_datetime_unix - from_datetime_unix, interval)
    span = Enum.max([span, 1])

    query = """
    SELECT time, SUM(events) as events_count
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
          0 AS events
        FROM numbers(?2)

        UNION ALL

        SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, count(e) as event
          FROM (
            SELECT any(event) as e, dt
            FROM #{@table}
            PREWHERE owner = ?3
            AND dt >= toDateTime(?4)
            AND dt <= toDateTime(?5)
            AND event NOT in (?6)
            GROUP BY owner, dt
          )
          GROUP BY time
      )
      GROUP BY time
      ORDER BY time
    """

    args = [interval, span, organization, from_datetime_unix, to_datetime_unix, @ignored_events]

    {query, args}
  end
end
