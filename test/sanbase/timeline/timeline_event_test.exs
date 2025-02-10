defmodule Sanbase.Timeline.TimelineEventTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Insight.Post
  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.UserList

  setup do
    clean_task_supervisor_children()

    user = insert(:user)

    approved_post = insert(:post, state: Post.approved_state())

    awaiting_approval_post = insert(:post, state: Post.awaiting_approval_state())

    {:ok, public_watchlist} =
      UserList.create_user_list(user, %{name: "My Public List", is_public: true})

    {:ok, private_watchlist} =
      UserList.create_user_list(user, %{name: "My Private List", is_public: false})

    %{
      approved_post: approved_post,
      awaiting_approval_post: awaiting_approval_post,
      user: user,
      public_watchlist: public_watchlist,
      private_watchlist: private_watchlist
    }
  end

  describe "#maybe_create_event_async for insights" do
    test "creates an event when approved insight is being published", %{
      approved_post: approved_post
    } do
      maybe_create_event_for_post(approved_post)

      assert_receive({_, {:ok, %TimelineEvent{}}})

      assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 1
    end

    test "does not create an event when not approved insight is being published", %{
      awaiting_approval_post: awaiting_approval_post
    } do
      maybe_create_event_for_post(awaiting_approval_post)

      refute_receive({_, {:ok, %TimelineEvent{}}})

      assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 0
    end
  end

  describe "#maybe_create_event_async for user_trigger" do
    test "creates an event when created user trigger is public", %{user: user} do
      UserTrigger.create_user_trigger(user, %{
        is_public: true,
        title: "test",
        settings: default_trigger_settings_string_keys()
      })

      assert_receive({_, {:ok, %TimelineEvent{}}})

      assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 1
    end

    test "does not create an event when created user trigger is not public", %{user: user} do
      UserTrigger.create_user_trigger(user, %{
        is_public: false,
        title: "test",
        settings: default_trigger_settings_string_keys()
      })

      refute_receive({_, {:ok, %TimelineEvent{}}})

      assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 0
    end
  end

  describe "#maybe_create_event_async for watchlists" do
    test "creates an event when updated watchlist is public and projects are updated", context do
      %{
        public_watchlist: public_watchlist,
        user: user
      } = context

      project = insert(:project)

      UserList.update_user_list(user, %{
        id: public_watchlist.id,
        list_items: [%{project_id: project.id}]
      })

      assert_receive({_, {:ok, %TimelineEvent{}}})

      assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 1
    end

    test "does not create an event when updated watchlist is not public", context do
      %{
        private_watchlist: private_watchlist,
        user: user
      } = context

      project = insert(:project)

      UserList.update_user_list(user, %{
        id: private_watchlist.id,
        list_items: [%{project_id: project.id}]
      })

      refute_receive({_, {:ok, %TimelineEvent{}}})

      assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 0
    end

    test "does not create an event when updated watchlist is public but does not update projects",
         context do
      %{public_watchlist: public_watchlist, user: user} = context

      UserList.update_user_list(user, %{id: public_watchlist.id, name: "New name"})

      refute_receive({_, {:ok, %TimelineEvent{}}})

      assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 0
    end
  end

  defp maybe_create_event_for_post(post) do
    event_type = TimelineEvent.publish_insight_type()
    publish_changeset = Post.publish_changeset(post, %{ready_state: Post.published()})
    post = Repo.update!(publish_changeset)
    TimelineEvent.maybe_create_event_async(event_type, post, publish_changeset)
  end

  defp default_trigger_settings_string_keys do
    %{
      "type" => "metric_signal",
      "metric" => "active_addresses_24h",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1d",
      "operation" => %{"percent_up" => 300.0}
    }
  end
end
