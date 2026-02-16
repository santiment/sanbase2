defmodule Sanbase.Email.SesEmailEvent do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          message_id: String.t(),
          email: String.t(),
          event_type: String.t(),
          bounce_type: String.t() | nil,
          bounce_sub_type: String.t() | nil,
          complaint_feedback_type: String.t() | nil,
          reject_reason: String.t() | nil,
          delay_type: String.t() | nil,
          smtp_response: String.t() | nil,
          timestamp: DateTime.t(),
          raw_data: map() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @event_types ~w(Send Reject Bounce Complaint Delivery DeliveryDelay)

  schema "ses_email_events" do
    field(:message_id, :string)
    field(:email, :string)
    field(:event_type, :string)
    field(:bounce_type, :string)
    field(:bounce_sub_type, :string)
    field(:complaint_feedback_type, :string)
    field(:reject_reason, :string)
    field(:delay_type, :string)
    field(:smtp_response, :string)
    field(:timestamp, :utc_datetime)
    field(:raw_data, :map)

    timestamps()
  end

  @fields [
    :message_id,
    :email,
    :event_type,
    :bounce_type,
    :bounce_sub_type,
    :complaint_feedback_type,
    :reject_reason,
    :delay_type,
    :smtp_response,
    :timestamp,
    :raw_data
  ]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required([:message_id, :email, :event_type, :timestamp])
    |> validate_inclusion(:event_type, @event_types)
  end

  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @spec list_events(keyword()) :: [t()]
  def list_events(opts \\ []) do
    base_query()
    |> apply_filters(opts)
    |> apply_pagination(opts)
    |> order_by([e], desc: e.timestamp)
    |> Repo.all()
  end

  @spec count_events(keyword()) :: non_neg_integer()
  def count_events(opts \\ []) do
    base_query()
    |> apply_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  @spec stats_since(DateTime.t()) :: map()
  def stats_since(since_datetime) do
    from(e in __MODULE__,
      where: e.inserted_at >= ^since_datetime,
      group_by: e.event_type,
      select: {e.event_type, count(e.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec event_types() :: [String.t()]
  def event_types, do: @event_types

  defp base_query, do: from(e in __MODULE__)

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_event_type(Keyword.get(opts, :event_type))
    |> maybe_filter_email(Keyword.get(opts, :email_search))
  end

  defp maybe_filter_event_type(query, nil), do: query
  defp maybe_filter_event_type(query, ""), do: query

  defp maybe_filter_event_type(query, event_type) do
    where(query, [e], e.event_type == ^event_type)
  end

  defp maybe_filter_email(query, nil), do: query
  defp maybe_filter_email(query, ""), do: query

  defp maybe_filter_email(query, search) do
    escaped =
      search
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    search_term = "%#{escaped}%"
    where(query, [e], ilike(e.email, ^search_term))
  end

  defp apply_pagination(query, opts) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, 50) |> max(1) |> min(100)
    offset = (page - 1) * page_size

    query
    |> limit(^page_size)
    |> offset(^offset)
  end
end
