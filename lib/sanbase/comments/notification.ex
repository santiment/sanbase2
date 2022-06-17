defmodule Sanbase.Comments.Notification do
  use Ecto.Schema

  require Logger

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Comment.{
    PostComment,
    TimelineEventComment,
    ChartConfigurationComment,
    WatchlistComment
  }

  alias Sanbase.Repo

  @default_avatar "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png"

  schema "comment_notifications" do
    field(:last_insight_comment_id, :integer)
    field(:last_timeline_event_comment_id, :integer)
    field(:last_chart_configuration_comment_id, :integer)
    field(:last_watchlist_comment_id, :integer)
    field(:notify_users_map, :map)

    timestamps()
  end

  @doc false
  def changeset(notifications, attrs) do
    notifications
    |> cast(attrs, [
      :last_insight_comment_id,
      :last_timeline_event_comment_id,
      :last_chart_configuration_comment_id,
      :last_watchlist_comment_id,
      :notify_users_map
    ])
    |> validate_required([
      :last_insight_comment_id,
      :last_timeline_event_comment_id,
      :last_chart_configuration_comment_id,
      :last_watchlist_comment_id,
      :notify_users_map
    ])
  end

  def get_last_record() do
    __MODULE__ |> last() |> Repo.one()
  end

  def create(params) do
    %__MODULE__{} |> changeset(params) |> Repo.insert()
  end

  def notify_users do
    data = build_ntf_events_map()

    data.notify_users_map
    |> Enum.each(fn {email, data} ->
      params = %{
        "total_number" => length(data),
        "events" => data
      }

      send_email(email, params)
    end)

    create(data)
  end

  def build_ntf_events_map() do
    last_comment_notification = get_last_record()

    recent_insight_comments =
      recent_comments_query(:insight, last_comment_notification) |> Repo.all()

    recent_timeline_event_comments =
      recent_comments_query(:timeline_event, last_comment_notification) |> Repo.all()

    recent_chart_configuration_comments =
      recent_comments_query(:chart_configuration, last_comment_notification) |> Repo.all()

    recent_watchlist_comments =
      recent_comments_query(:watchlist, last_comment_notification) |> Repo.all()

    notify_map(recent_chart_configuration_comments, :chart_configuration)

    notify_users_map =
      notify_map(recent_insight_comments, :insight)
      |> merge_events(notify_map(recent_timeline_event_comments, :timeline_event))
      |> merge_events(notify_map(recent_chart_configuration_comments, :chart_configuration))
      |> merge_events(notify_map(recent_watchlist_comments, :watchlist))

    %{
      notify_users_map: notify_users_map,
      last_insight_comment_id: last_sent_id(recent_insight_comments, :insight),
      last_timeline_event_comment_id:
        last_sent_id(recent_timeline_event_comments, :timeline_event),
      last_chart_configuration_comment_id:
        last_sent_id(recent_chart_configuration_comments, :chart_configuration),
      last_watchlist_comment_id: last_sent_id(recent_watchlist_comments, :watchlist)
    }
  end

  def notify_map(recent_comments, type) do
    recent_comments
    |> Enum.reduce(%{}, fn comment, acc ->
      acc
      |> ntf_previously_commented(comment, type)
      |> ntf_author(comment, type)
      |> ntf_reply(comment, type)
    end)
  end

  # private functions

  defp ntf_author(
         notify_users_map,
         %PostComment{
           comment: %{user_id: commenter_id},
           post: %{user_id: author_id}
         },
         _
       )
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(
         notify_users_map,
         %TimelineEventComment{
           comment: %{user_id: commenter_id},
           timeline_event: %{user_id: author_id}
         },
         _
       )
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(
         notify_users_map,
         %ChartConfigurationComment{
           comment: %{user_id: commenter_id},
           chart_configuration: %{user_id: author_id}
         },
         _
       )
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(
         notify_users_map,
         %WatchlistComment{
           comment: %{user_id: commenter_id},
           watchlist: %{user_id: author_id}
         },
         _
       )
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(
         notify_users_map,
         %PostComment{post: %{user: %{email: email}}} = comment,
         :insight
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment, "ntf_author", :insight)
  end

  defp ntf_author(
         notify_users_map,
         %TimelineEventComment{timeline_event: %{user: %{email: email}}} = comment,
         :timeline_event
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment, "ntf_author", :timeline_event)
  end

  defp ntf_author(
         notify_users_map,
         %ChartConfigurationComment{chart_configuration: %{user: %{email: email}}} = comment,
         :chart_configuration
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment, "ntf_author", :chart_configuration)
  end

  defp ntf_author(
         notify_users_map,
         %WatchlistComment{watchlist: %{user: %{email: email}}} = comment,
         :watchlist
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment, "ntf_author", :watchlist)
  end

  defp ntf_author(notify_users_map, _, _), do: notify_users_map

  defp ntf_reply(
         notify_users_map,
         %{
           comment: %{
             user_id: commenter_id,
             parent: %{user_id: parrent_commenter_id}
           }
         },
         _
       )
       when commenter_id == parrent_commenter_id,
       do: notify_users_map

  defp ntf_reply(
         notify_users_map,
         %{comment: %{parent: %{user: %{email: email}}}} = comment,
         entity
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment, "ntf_reply", entity)
  end

  defp ntf_reply(notify_users_map, _, _), do: notify_users_map

  # Get comments on the same post added before certain comment
  defp ntf_previously_commented(notify_users_map, comment, entity) do
    emails =
      previous_comments_query(comment, entity)
      |> Repo.all()
      |> Enum.reject(&(&1.comment.id == comment.comment.parent_id))
      |> Enum.map(& &1.comment.user.email)
      |> Enum.reject(&(&1 == nil || &1 == comment.comment.user.email))
      |> Enum.dedup()

    put_event_in_map(
      notify_users_map,
      emails,
      comment,
      "ntf_previously_commented",
      entity
    )
  end

  defp put_event_in_map(notify_users_map, emails, comment, event, entity) when is_list(emails) do
    Enum.reduce(emails, notify_users_map, fn email, acc ->
      put_event_in_map(acc, email, comment, event, entity)
    end)
  end

  defp put_event_in_map(notify_users_map, email, post_comment, event_type, :insight) do
    comment = post_comment.comment
    events = notify_users_map[email] || []

    events = events |> Enum.reject(fn event -> event.comment_id == post_comment.id end)

    new_event = %{
      comment_id: post_comment.id,
      entity: "insight",
      event: event_type,
      comment_text: comment.content,
      entity_link: "https://insights.santiment.net/read/#{post_comment.post_id}",
      entity_name: post_comment.post.title,
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, email, events ++ [new_event])
  end

  defp put_event_in_map(notify_users_map, email, feed_comment, event_type, :timeline_event) do
    comment = feed_comment.comment
    events = notify_users_map[email] || []

    events = events |> Enum.reject(fn event -> event.comment_id == feed_comment.id end)

    new_event = %{
      comment_id: feed_comment.id,
      entity: "timeline_event",
      event: event_type,
      comment_text: comment.content,
      entity_link: "",
      entity_name: feed_entity_title(feed_comment.timeline_event_id),
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, email, events ++ [new_event])
  end

  defp put_event_in_map(notify_users_map, email, cc_comment, event_type, :chart_configuration) do
    comment = cc_comment.comment
    events = notify_users_map[email] || []

    events = events |> Enum.reject(fn event -> event.comment_id == cc_comment.id end)

    new_event = %{
      comment_id: cc_comment.id,
      entity: "chart_configuration",
      event: event_type,
      comment_text: comment.content,
      entity_link: "",
      entity_name: cc_comment.chart_configuration.title || "",
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, email, events ++ [new_event])
  end

  defp put_event_in_map(notify_users_map, email, watchlist_comment, event_type, :watchlist) do
    comment = watchlist_comment.comment
    events = notify_users_map[email] || []

    events = events |> Enum.reject(fn event -> event.comment_id == watchlist_comment.id end)

    entity_type =
      case watchlist_comment.watchlist.is_screener do
        true -> "screener"
        false -> "watchlist"
      end

    new_event = %{
      comment_id: watchlist_comment.id,
      entity: entity_type,
      event: event_type,
      comment_text: comment.content,
      entity_link: "",
      entity_name: watchlist_comment.watchlist.name,
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, email, events ++ [new_event])
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

  defp recent_comments_query(:chart_configuration, last_comment_notification) do
    last_comment_id =
      if last_comment_notification,
        do: last_comment_notification.last_chart_configuration_comment_id,
        else: 0

    yesterday = Timex.shift(Timex.now(), days: -1)

    from(t in ChartConfigurationComment,
      where: t.id > ^last_comment_id and t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], chart_configuration: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:watchlist, last_comment_notification) do
    last_comment_id =
      if last_comment_notification,
        do: last_comment_notification.last_watchlist_comment_id,
        else: 0

    yesterday = Timex.shift(Timex.now(), days: -1)

    from(t in WatchlistComment,
      where: t.id > ^last_comment_id and t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], watchlist: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp previous_comments_query(post_comment, :insight) do
    from(p in PostComment,
      where:
        p.post_id == ^post_comment.post.id and
          p.comment_id != ^post_comment.comment.id and
          p.inserted_at <= ^post_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp previous_comments_query(timeline_event_comment, :timeline_event) do
    from(t in TimelineEventComment,
      where:
        t.timeline_event_id == ^timeline_event_comment.timeline_event.id and
          t.comment_id != ^timeline_event_comment.comment.id and
          t.inserted_at <= ^timeline_event_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp previous_comments_query(cc_comment, :chart_configuration) do
    from(ccc in ChartConfigurationComment,
      where:
        ccc.chart_configuration_id == ^cc_comment.chart_configuration.id and
          ccc.comment_id != ^cc_comment.comment.id and
          ccc.inserted_at <= ^cc_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp previous_comments_query(watchlist_comment, :watchlist) do
    from(wc in WatchlistComment,
      where:
        wc.watchlist_id == ^watchlist_comment.watchlist.id and
          wc.comment_id != ^watchlist_comment.comment.id and
          wc.inserted_at <= ^watchlist_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp last_sent_id(recent_comments, type) do
    recent_comments
    |> List.last()
    |> last_id(get_last_record(), type)
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

  defp last_id(
         nil,
         %__MODULE__{last_chart_configuration_comment_id: last_id},
         :chart_configuration
       ),
       do: last_id

  defp last_id(nil, %__MODULE__{last_watchlist_comment_id: last_id}, :watchlist),
    do: last_id

  defp last_id(%PostComment{id: id}, _, _), do: id
  defp last_id(%TimelineEventComment{id: id}, _, _), do: id
  defp last_id(%ChartConfigurationComment{id: id}, _, _), do: id
  defp last_id(%WatchlistComment{id: id}, _, _), do: id

  defp get_name(user) do
    user.username || "Anon"
  end

  defp feed_entity_title(timeline_event_id) do
    case Sanbase.Timeline.TimelineEvent.by_id!(timeline_event_id, []) do
      %{post: %{title: title}} -> title
      %{user_list: %{name: name}} -> name
      %{user_trigger: %{trigger: %{title: title}}} -> title
      _ -> "feed event"
    end
  end

  def send_email(email, params) do
    Sanbase.Email.Template.comment_notification_template()
    |> Sanbase.MandrillApi.send(email, params, %{
      merge_language: "handlebars"
    })
  end

  defp merge_events(map1, map2) do
    Enum.reduce(map2, map1, fn {email, list}, acc ->
      new_list = list ++ (acc[email] || [])
      Map.put(acc, email, new_list)
    end)
  end
end
