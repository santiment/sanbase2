defmodule Sanbase.Comments.Notification do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Insight.PostComment
  alias Sanbase.Timeline.TimelineEventComment
  alias Sanbase.Repo

  schema "comment_notifications" do
    field(:last_insight_comment_id, :integer)
    field(:last_timeline_event_comment_id, :integer)
    field(:notify_users_map, :map)

    timestamps()
  end

  @doc false
  def changeset(notifications, attrs) do
    notifications
    |> cast(attrs, [:last_insight_comment_id, :last_timeline_event_comment_id, :notify_users_map])
    |> validate_required([
      :last_insight_comment_id,
      :last_timeline_event_comment_id,
      :notify_users_map
    ])
  end

  def get_last_record() do
    __MODULE__ |> last() |> Repo.one()
  end

  def create(params) do
    %__MODULE__{} |> changeset(params) |> Repo.insert()
  end

  def notify_users() do
    last_comment_notification = get_last_record()

    recent_insight_comments =
      recent_comments_query(:insight, last_comment_notification) |> Repo.all()

    recent_timeline_event_comments =
      recent_comments_query(:timeline_event, last_comment_notification) |> Repo.all()

    notify_users_map = %{
      insight: notify_map(:insight, recent_insight_comments),
      timeline_event: notify_map(:timeline_event, recent_timeline_event_comments)
    }

    last_insight_comment_id =
      recent_insight_comments |> List.last() |> last_id(last_comment_notification, :insight)

    last_timeline_event_comment_id =
      recent_timeline_event_comments
      |> List.last()
      |> last_id(last_comment_notification, :timeline_event)

    create(%{
      notify_users_map: notify_users_map,
      last_insight_comment_id: last_insight_comment_id,
      last_timeline_event_comment_id: last_timeline_event_comment_id
    })
  end

  def notify_map(type, recent_comments) do
    recent_comments
    |> Enum.reduce(%{}, fn comment, acc ->
      acc
      |> ntf_author(comment, type)
      |> ntf_reply(comment, type)
      |> ntf_previously_commented(comment, type)
    end)
  end

  # private functions

  defp ntf_author(
         notify_users_map,
         %PostComment{post: %{user: %{email: email}}} = comment,
         :insight
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_author")
  end

  defp ntf_author(
         notify_users_map,
         %TimelineEventComment{timeline_event: %{user: %{email: email}}} = comment,
         :timeline_event
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_author")
  end

  defp ntf_author(notify_users_map, _, _), do: notify_users_map

  defp ntf_reply(
         notify_users_map,
         %PostComment{comment: %{parent: %{user: %{email: email}}}} = comment,
         :insight
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_reply")
  end

  defp ntf_reply(
         notify_users_map,
         %TimelineEventComment{comment: %{parent: %{user: %{email: email}}}} = comment,
         :timeline_event
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_reply")
  end

  defp ntf_reply(notify_users_map, _, _), do: notify_users_map

  # Get comments on the same post added before certain comment
  defp ntf_previously_commented(notify_users_map, comment, type) do
    emails =
      previous_comments_query(comment, type)
      |> Repo.all()
      |> Enum.reject(&(&1.comment.id == comment.comment.parent_id))
      |> Enum.map(& &1.comment.user.email)
      |> Enum.reject(&(&1 == nil || &1 == comment.comment.user.email))

    put_event_in_map(
      notify_users_map,
      emails,
      comment.id,
      "ntf_previously_commented"
    )
  end

  defp put_event_in_map(notify_users_map, emails, comment_id, event) when is_list(emails) do
    Enum.reduce(emails, notify_users_map, fn email, acc ->
      put_event_in_map(acc, email, comment_id, event)
    end)
  end

  defp put_event_in_map(notify_users_map, email, comment_id, event) do
    events = notify_users_map[email][comment_id][:events] || []
    comment_map = %{comment_id => events ++ [event]}

    Map.update(notify_users_map, email, comment_map, fn current_map ->
      Map.merge(current_map, comment_map)
    end)
  end

  defp recent_comments_query(:insight, last_comment_notification) do
    last_insight_comment_id =
      if last_comment_notification, do: last_comment_notification.last_insight_comment_id, else: 0

    yesterday = Timex.shift(Timex.now(), days: -1)

    from(p in PostComment,
      where: p.id > ^last_insight_comment_id and p.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], post: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:timeline_event, last_comment_notification) do
    last_timeline_event_comment_id =
      if last_comment_notification,
        do: last_comment_notification.last_timeline_event_comment_id,
        else: 0

    yesterday = Timex.shift(Timex.now(), days: -1)

    from(t in TimelineEventComment,
      where: t.id > ^last_timeline_event_comment_id and t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], timeline_event: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp previous_comments_query(post_comment, :insight) do
    from(p in PostComment,
      where:
        p.post_id == ^post_comment.post.id and p.comment_id != ^post_comment.comment.id and
          p.inserted_at < ^post_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp previous_comments_query(timeline_event_comment, :timeline_event) do
    from(t in TimelineEventComment,
      where:
        t.timeline_event_id == ^timeline_event_comment.timeline_event.id and
          t.comment_id != ^timeline_event_comment.comment.id and
          t.inserted_at < ^timeline_event_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp last_id(nil, nil, _), do: 0

  defp last_id(nil, %__MODULE__{last_insight_comment_id: last_insight_comment_id}, :insight),
    do: last_insight_comment_id

  defp last_id(
         nil,
         %__MODULE__{last_timeline_event_comment_id: last_timeline_event_comment_id},
         :timeline_event
       ),
       do: last_timeline_event_comment_id

  defp last_id(%PostComment{id: id}, _, _), do: id
  defp last_id(%TimelineEventComment{id: id}, _, _), do: id
end
