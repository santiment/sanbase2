defmodule Sanbase.Comments.Notification do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Comment.ChartConfigurationComment
  alias Sanbase.Comment.PostComment
  alias Sanbase.Comment.TimelineEventComment
  alias Sanbase.Comment.WatchlistComment
  alias Sanbase.Repo
  alias Sanbase.UserList

  require Logger

  @default_avatar "https://production-sanbase-images.s3.amazonaws.com/uploads/684aec65d98c952d6a29c8f0fbdcaea95787f1d4e752e62316e955a84ae97bf5_1588611275860_default-avatar.png"

  def notify_users do
    Enum.each(notify_users_map(), fn {email, data} ->
      send_email(email, data)
    end)
  end

  def notify_users_map do
    comments_map = comments_ntf_map()
    votes_map = votes_ntf_map()

    {comments_and_votes_map, rcpts_ids} = comments_and_votes_map(comments_map, votes_map)
    votes_only_map = votes_only_map(votes_map, rcpts_ids)

    Map.merge(comments_and_votes_map, votes_only_map)
  end

  def comments_ntf_map do
    recent_insight_comments = :insight |> recent_comments_query() |> Repo.all()
    recent_timeline_event_comments = :timeline_event |> recent_comments_query() |> Repo.all()

    recent_chart_configuration_comments =
      :chart_configuration |> recent_comments_query() |> Repo.all()

    recent_watchlist_comments = :watchlist |> recent_comments_query() |> Repo.all()

    recent_insight_comments
    |> build_notify_map(:insight)
    |> merge_events(build_notify_map(recent_timeline_event_comments, :timeline_event))
    |> merge_events(build_notify_map(recent_chart_configuration_comments, :chart_configuration))
    |> merge_events(build_notify_map(recent_watchlist_comments, :watchlist))
  end

  def build_notify_map(recent_comments, type) do
    Enum.reduce(recent_comments, %{}, fn comment, acc ->
      acc
      |> ntf_author(comment, type)
      |> ntf_reply(comment, type)
    end)
  end

  def votes_map do
    Repo.all(recent_votes_query())
  end

  def votes_ntf_map do
    # get votes for last 24 hours
    recent_votes_query()
    |> Repo.all()
    |> Enum.map(&separate_into_entities/1)
    |> Enum.group_by(fn vote -> vote.author_id end)
    |> Map.new(&build_votes_ntf_map/1)
  end

  # private functions

  defp votes_only_map(votes_map, rcpts_ids) do
    votes_map
    |> Map.reject(fn {key, _val} -> key in rcpts_ids end)
    |> Enum.reduce(%{}, fn {user_id, votes}, acc ->
      user = Sanbase.Accounts.get_user!(user_id)

      data = %{
        username: get_name(user),
        comments_count: 0,
        likes_count: Enum.reduce(votes, 0, fn vote, acc -> acc + vote.likes_count end),
        comments: [],
        likes: votes
      }

      Map.put(acc, user.email, data)
    end)
  end

  defp comments_and_votes_map(comments_map, votes_map) do
    Enum.reduce(comments_map, {%{}, []}, fn {user_id, comments}, {ntf_users_map, rcpts} ->
      user = Sanbase.Accounts.get_user!(user_id)
      votes = votes_map[user_id] || []

      data = %{
        username: get_name(user),
        comments_count: length(comments),
        likes_count: Enum.reduce(votes, 0, fn vote, acc -> acc + vote.likes_count end),
        comments: maybe_update_comments(comments),
        likes: votes
      }

      ntf_users_map = Map.put(ntf_users_map, user.email, data)
      rcpts = rcpts ++ [user_id]

      {ntf_users_map, rcpts}
    end)
  end

  def maybe_update_comments(comments) do
    Enum.map(comments, fn
      %{type: "reply"} = comment -> Map.put(comment, :reply_to_text, "reply")
      comment -> Map.put(comment, :reply_to_text, false)
    end)
  end

  defp separate_into_entities(vote) do
    {entity, entity_id, title, link, author_id} =
      cond do
        not is_nil(vote.post_id) ->
          {"insight", vote.post_id, vote.post.title, deduce_entity_link(vote.post_id, :insight), vote.post.user_id}

        not is_nil(vote.watchlist_id) ->
          {"#{watchlist_type(vote.watchlist)}", vote.watchlist_id, vote.watchlist.name,
           deduce_entity_link(vote.watchlist, :watchlist), vote.watchlist.user_id}

        not is_nil(vote.chart_configuration_id) ->
          {"chart layout", vote.chart_configuration_id, vote.chart_configuration.title,
           deduce_entity_link(vote.chart_configuration, :chart_configuration), vote.chart_configuration.user_id}
      end

    %{
      entity: entity,
      entity_id: entity_id,
      link: link,
      title: title,
      user: vote.user,
      author_id: author_id
    }
  end

  defp build_votes_ntf_map({author_id, votes}) do
    result =
      votes
      |> Enum.group_by(fn vote -> {vote.entity, vote.entity_id} end)
      |> Enum.map(fn {{_entity, _entity_id}, votes} ->
        vote0 = Enum.at(votes, 0)
        avatar_url = vote0.user.avatar_url || @default_avatar
        usernames = Enum.map(votes, fn vote -> get_name(vote.user) end)

        result =
          vote0
          |> Map.take([:entity, :entity_id, :link, :title])
          |> Map.put(:usernames, Enum.join(usernames, ", "))
          |> Map.put(:avatar_url, avatar_url)
          |> Map.put(:likes_count, length(usernames))

        case length(usernames) do
          num when num > 3 -> Map.put(result, :rest, num - 3)
          _ -> Map.put(result, :rest, false)
        end
      end)

    {author_id, result}
  end

  defp ntf_author(notify_users_map, %PostComment{comment: %{user_id: commenter_id}, post: %{user_id: author_id}}, _)
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(
         notify_users_map,
         %TimelineEventComment{comment: %{user_id: commenter_id}, timeline_event: %{user_id: author_id}},
         _
       )
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(
         notify_users_map,
         %ChartConfigurationComment{comment: %{user_id: commenter_id}, chart_configuration: %{user_id: author_id}},
         _
       )
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(
         notify_users_map,
         %WatchlistComment{comment: %{user_id: commenter_id}, watchlist: %{user_id: author_id}},
         _
       )
       when commenter_id == author_id,
       do: notify_users_map

  defp ntf_author(notify_users_map, %PostComment{post: %{user_id: user_id}} = comment, :insight) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :insight)
  end

  defp ntf_author(notify_users_map, %TimelineEventComment{timeline_event: %{user_id: user_id}} = comment, :timeline_event) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :timeline_event)
  end

  defp ntf_author(
         notify_users_map,
         %ChartConfigurationComment{chart_configuration: %{user_id: user_id}} = comment,
         :chart_configuration
       ) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :chart_configuration)
  end

  defp ntf_author(notify_users_map, %WatchlistComment{watchlist: %{user_id: user_id}} = comment, :watchlist) do
    put_event_in_map(notify_users_map, user_id, comment, "comment", :watchlist)
  end

  defp ntf_author(notify_users_map, _, _), do: notify_users_map

  defp ntf_reply(notify_users_map, %{comment: %{user_id: commenter_id, parent: %{user_id: parrent_commenter_id}}}, _)
       when commenter_id == parrent_commenter_id,
       do: notify_users_map

  defp ntf_reply(notify_users_map, %{comment: %{parent: %{user_id: user_id}}} = comment, entity) do
    put_event_in_map(notify_users_map, user_id, comment, "reply", entity)
  end

  defp ntf_reply(notify_users_map, _, _), do: notify_users_map

  defp put_event_in_map(notify_users_map, user_ids, comment, event, entity) when is_list(user_ids) do
    Enum.reduce(user_ids, notify_users_map, fn user_id, acc ->
      put_event_in_map(acc, user_id, comment, event, entity)
    end)
  end

  defp put_event_in_map(notify_users_map, user_id, post_comment, event_type, :insight) do
    comment = post_comment.comment
    events = notify_users_map[user_id] || []

    events = Enum.reject(events, fn event -> event.comment_id == post_comment.id end)

    new_event = %{
      comment_id: comment.id,
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

    events = Enum.reject(events, fn event -> event.comment_id == feed_comment.id end)

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

    events = Enum.reject(events, fn event -> event.comment_id == cc_comment.id end)

    new_event = %{
      comment_id: cc_comment.id,
      entity: "chart layout",
      type: event_type,
      comment_text: comment.content,
      link: deduce_entity_link(cc_comment.chart_configuration, :chart_configuration),
      title: cc_comment.chart_configuration.title || "",
      username: get_name(comment.user),
      avatar_url: comment.user.avatar_url || @default_avatar
    }

    Map.put(notify_users_map, user_id, events ++ [new_event])
  end

  defp put_event_in_map(notify_users_map, user_id, watchlist_comment, event_type, :watchlist) do
    comment = watchlist_comment.comment
    events = notify_users_map[user_id] || []

    events = Enum.reject(events, fn event -> event.comment_id == watchlist_comment.id end)

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
    yesterday = Timex.shift(DateTime.utc_now(), days: -1)

    from(p in PostComment,
      where: p.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], post: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:timeline_event) do
    yesterday =
      Timex.shift(DateTime.utc_now(),
        days: -1
      )

    from(t in TimelineEventComment,
      where: t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], timeline_event: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:chart_configuration) do
    yesterday = Timex.shift(DateTime.utc_now(), days: -1)

    from(t in ChartConfigurationComment,
      where: t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], chart_configuration: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:watchlist) do
    yesterday = Timex.shift(DateTime.utc_now(), days: -1)

    from(wc in WatchlistComment,
      where: wc.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], watchlist: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_votes_query do
    yesterday = Timex.shift(DateTime.utc_now(), days: -1)

    from(v in Sanbase.Vote,
      where: v.inserted_at > ^yesterday,
      preload: [:post, :watchlist, :timeline_event, :chart_configuration, :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp get_name(user_id) when is_number(user_id) do
    user = Sanbase.Accounts.get_user!(user_id)
    get_name(user)
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
    Sanbase.TemplateMailer.send(
      email,
      Sanbase.Email.Template.comment_notification_template(),
      params
    )
  end

  defp merge_events(map1, map2) do
    Enum.reduce(map2, map1, fn {user_id, list}, acc ->
      new_list = list ++ (acc[user_id] || [])
      Map.put(acc, user_id, new_list)
    end)
  end

  defp watchlist_type(watchlist) do
    if watchlist.is_screener do
      "screener"
    else
      "watchlist"
    end
  end

  defp deduce_entity_link(insight_id, :insight) do
    SanbaseWeb.Endpoint.frontend_url() <> "/insights/read/#{insight_id}"
  end

  defp deduce_entity_link(_chart_configuration, :timeline_event) do
    SanbaseWeb.Endpoint.frontend_url()
  end

  defp deduce_entity_link(chart_configuration, :chart_configuration) do
    SanbaseWeb.Endpoint.frontend_url() <> "/charts/-#{chart_configuration.id}"
  end

  defp deduce_entity_link(watchlist, :watchlist) do
    case {UserList.screener?(watchlist), UserList.type(watchlist)} do
      {true, _type} ->
        SanbaseWeb.Endpoint.frontend_url() <> "/screener/#{watchlist.id}"

      {false, :project} ->
        SanbaseWeb.Endpoint.frontend_url() <> "/watchlist/projects/#{watchlist.id}"

      {false, :blockchain_address} ->
        SanbaseWeb.Endpoint.frontend_url() <> "/watchlist/addresses/#{watchlist.id}"
    end
  end
end
