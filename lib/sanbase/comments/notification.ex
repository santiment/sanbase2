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
  alias Sanbase.UserList

  @default_avatar "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png"
  @mock_data %{
    username: "@tsetso",
    comments_count: 2,
    likes_count: 12,
    comments: [
      %{
        entity: "Insight",
        comment_text: "Comment body text",
        link: "https://insights.santiment.net/read/7007",
        title: "The wall of worry",
        username: "@aishray9",
        avatar_url:
          "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png",
        type: "comment"
      },
      %{
        entity: "Insight",
        comment_text: "This us a comment reply",
        link: "https://insights.santiment.net/read/7007",
        title: "The wall of worry",
        username: "@alabala",
        avatar_url:
          "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png",
        type: "reply",
        reply_to_text:
          "Could you explain what those line actually represent compared to whale line"
      }
    ],
    likes: [
      %{
        entity: "Chart layout",
        link: "https://app.santiment.net",
        title: "Some interesting chart layout",
        usernames: "@u1, @u2, @u3",
        rest: 7,
        avatar_url:
          "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png"
      },
      %{
        entity: "Insight",
        link: "https://app.santiment.net",
        title: "Some interesting insight",
        usernames: "@pesho, @gosho",
        avatar_url:
          "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png",
        rest: 0
      }
    ]
  }

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
    data = comments_ntf_map()

    data.notify_users_map
    |> Enum.each(fn {user_id, data} ->
      params = %{
        "total_number" => length(data),
        "events" => data
      }

      send_email(user_id, params)
    end)

    create(data)
  end

  def votes_ntf_map() do
    # get votes for last 24 hours
    recent_votes_query()
    |> Repo.all()
    |> Enum.map(fn vote ->
      {entity, entity_id, title, link, author_id} =
        cond do
          not is_nil(vote.post_id) ->
            {:insight, vote.post_id, vote.post.title, deduce_entity_link(vote.post_id, :insight),
             vote.post.user_id}

          not is_nil(vote.wathlist_id) ->
            {watchlist_type(vote.wathlist), vote.watchlist_id, vote.wathlist.name,
             deduce_entity_link(vote.watchlist, :watchlist), vote.watchlist.user_id}

          not is_nil(vote.chart_configuration) ->
            {:chart_configuration, vote.chart_configuration_id, vote.chart_configuration.title,
             deduce_entity_link(vote.chart_configuration, :chart_configuration),
             vote.chart_configuration.user_id}
        end

      %{
        entity: entity,
        entity_id: entity_id,
        link: link,
        title: title,
        user: vote.user,
        author_id: author_id
      }
    end)
    |> Enum.group_by(fn vote -> vote.author_id end)
    |> Enum.into(%{}, fn {author_id, votes} ->
      rest =
        Enum.group_by(votes, fn vote -> {vote.entity, vote.entity_id} end)
        |> Enum.map(fn {{entity, entity_id}, votes} ->
          vote0 = Enum.at(votes, 0)
          avatar_url = vote0.user.avatar_url || @default_avatar
          usernames = votes |> Enum.map(fn vote -> "@" <> get_name(vote.user) end)

          result = Map.take(vote0, [:entity, :entity_id, :link, :title])
          result = Map.put(result, :usernames, usernames)

          result =
            case length(usernames) do
              num when num > 3 -> Map.put(result, :rest, num - 3)
              _ -> Map.put(result, :rest, 0)
            end

          result
        end)

      {author_id, rest}
    end)
  end

  def comments_ntf_map() do
    recent_insight_comments = recent_comments_query(:insight) |> Repo.all()
    recent_timeline_event_comments = recent_comments_query(:timeline_event) |> Repo.all()

    recent_chart_configuration_comments =
      recent_comments_query(:chart_configuration) |> Repo.all()

    recent_watchlist_comments = recent_comments_query(:watchlist) |> Repo.all()

    notify_map(recent_insight_comments, :insight)
    |> merge_events(notify_map(recent_timeline_event_comments, :timeline_event))
    |> merge_events(notify_map(recent_chart_configuration_comments, :chart_configuration))
    |> merge_events(notify_map(recent_watchlist_comments, :watchlist))
  end

  def notify_map(recent_comments, type) do
    recent_comments
    |> Enum.reduce(%{}, fn comment, acc ->
      acc
      |> ntf_author(comment, type)
      |> ntf_reply(comment, type)
    end)
  end

  def votes_map do
    recent_votes_query() |> Repo.all()
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
         %PostComment{post: %{user_id: user_id}} = comment,
         :insight
       ) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :insight)
  end

  defp ntf_author(
         notify_users_map,
         %TimelineEventComment{timeline_event: %{user_id: user_id}} = comment,
         :timeline_event
       ) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :timeline_event)
  end

  defp ntf_author(
         notify_users_map,
         %ChartConfigurationComment{chart_configuration: %{user_id: user_id}} = comment,
         :chart_configuration
       ) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :chart_configuration)
  end

  defp ntf_author(
         notify_users_map,
         %WatchlistComment{watchlist: %{user_id: user_id}} = comment,
         :watchlist
       ) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :watchlist)
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
         %{comment: %{parent: %{user_id: user_id}}} = comment,
         entity
       ) do
    put_event_in_map(notify_users_map, user_id, comment, "reply", entity)
  end

  defp ntf_reply(notify_users_map, _, _), do: notify_users_map

  defp put_event_in_map(notify_users_map, user_ids, comment, event, entity)
       when is_list(user_ids) do
    Enum.reduce(user_ids, notify_users_map, fn user_id, acc ->
      put_event_in_map(acc, user_id, comment, event, entity)
    end)
  end

  defp put_event_in_map(notify_users_map, user_id, post_comment, event_type, :insight) do
    comment = post_comment.comment
    events = notify_users_map[user_id] || []

    events = events |> Enum.reject(fn event -> event.comment_id == post_comment.id end)

    new_event = %{
      comment_id: post_comment.id,
      entity: "insight",
      type: event_type,
      comment_text: comment.content,
      link: "https://insights.santiment.net/read/#{post_comment.post_id}",
      title: post_comment.post.title,
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, user_id, events ++ [new_event])
  end

  defp put_event_in_map(notify_users_map, user_id, feed_comment, event_type, :timeline_event) do
    comment = feed_comment.comment
    events = notify_users_map[user_id] || []

    events = events |> Enum.reject(fn event -> event.comment_id == feed_comment.id end)

    new_event = %{
      comment_id: feed_comment.id,
      entity: "feed",
      type: event_type,
      comment_text: comment.content,
      link: deduce_entity_link(feed_comment.timeline_event, :timeline_event),
      title: feed_entity_title(feed_comment.timeline_event_id),
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, user_id, events ++ [new_event])
  end

  defp put_event_in_map(notify_users_map, user_id, cc_comment, event_type, :chart_configuration) do
    comment = cc_comment.comment
    events = notify_users_map[user_id] || []

    events = events |> Enum.reject(fn event -> event.comment_id == cc_comment.id end)

    new_event = %{
      comment_id: cc_comment.id,
      entity: "chart layout",
      type: event_type,
      comment_text: comment.content,
      link: deduce_entity_link(cc_comment.chart_configuration, :timeline_event),
      title: cc_comment.chart_configuration.title || "",
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, user_id, events ++ [new_event])
  end

  defp put_event_in_map(notify_users_map, user_id, watchlist_comment, event_type, :watchlist) do
    comment = watchlist_comment.comment
    events = notify_users_map[user_id] || []

    events = events |> Enum.reject(fn event -> event.comment_id == watchlist_comment.id end)

    new_event = %{
      comment_id: watchlist_comment.id,
      entity: watchlist_type(watchlist_comment.watchlist),
      type: event_type,
      comment_text: comment.content,
      link: deduce_entity_link(watchlist_comment.watchlist, :watchlist),
      title: watchlist_comment.watchlist.name,
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, user_id, events ++ [new_event])
  end

  defp recent_comments_query(:insight) do
    yesterday = Timex.shift(Timex.now(), days: -1)

    from(p in PostComment,
      where: p.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], post: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:timeline_event) do
    yesterday =
      Timex.shift(Timex.now(),
        days: -1
      )

    from(t in TimelineEventComment,
      where: t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], timeline_event: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:chart_configuration) do
    yesterday = Timex.shift(Timex.now(), days: -1)

    from(t in ChartConfigurationComment,
      where: t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], chart_configuration: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:watchlist) do
    yesterday = Timex.shift(Timex.now(), days: -1)

    from(wc in WatchlistComment,
      where: wc.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], watchlist: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_votes_query() do
    yesterday = Timex.shift(Timex.now(), days: -1)

    from(v in Sanbase.Vote,
      where: v.inserted_at > ^yesterday,
      preload: [:post, :watchlist, :timeline_event, :chart_configuration, :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp get_name(user) do
    "@" <> (user.username || "Anon")
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
    Enum.reduce(map2, map1, fn {user_id, list}, acc ->
      new_list = list ++ (acc[user_id] || [])
      Map.put(acc, user_id, new_list)
    end)
  end

  defp deduce_entity_link(insight_id, :insight) do
    SanbaseWeb.Endpoint.frontend_url() <> "/read/#{insight_id}"
  end

  defp deduce_entity_link(chart_configuration, :timeline_event) do
    SanbaseWeb.Endpoint.frontend_url()
  end

  defp deduce_entity_link(chart_configuration, :chart_configuration) do
    SanbaseWeb.Endpoint.frontend_url() <> "/charts/-#{chart_configuration.id}"
  end

  defp watchlist_type(watchlist) do
    case watchlist.is_screener do
      true -> :screener
      false -> :watchlist
    end
  end

  defp deduce_entity_link(watchlist, :watchlist) do
    case {UserList.is_screener?(watchlist), UserList.type(watchlist)} do
      {true, _type} ->
        SanbaseWeb.Endpoint.frontend_url() <> "/screener/#{watchlist.id}"

      {false, :project} ->
        SanbaseWeb.Endpoint.frontend_url() <> "/watchlist/projects/#{watchlist.id}"

      {false, :blockchain_address} ->
        SanbaseWeb.Endpoint.frontend_url() <> "/watchlist/addresses/#{watchlist.id}"
    end
  end
end
