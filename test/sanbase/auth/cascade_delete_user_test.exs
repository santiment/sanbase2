defmodule Sanbase.CascadeDeleteUserTest do
  use Sanbase.DataCase

  alias Sanbase.Timeline.TimelineEvent
  import Sanbase.Factory

  test "delete user and all its associations" do
    user = insert(:user)
    user2 = insert(:user)
    role_san_family = insert(:role_san_family)

    Sanbase.Accounts.LinkedUser.create(user.id, user2.id)
    _ = insert(:subscription_pro_sanbase, user: user)
    _ = insert(:watchlist, user: user)
    _ = insert(:user_role, user: user, role: role_san_family)
    query = insert(:query, user: user)
    dashboard = insert(:dashboard, user: user)

    _dashboard_query_mapping =
      Sanbase.Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

    {:ok, _} =
      Sanbase.Comments.EntityComment.create_and_link(
        :dashboard,
        dashboard.id,
        user.id,
        nil,
        "some comment"
      )

    {:ok, _} = Sanbase.Menus.create_menu(%{name: "MyMenu"}, user.id)

    user_trigger = insert(:user_trigger, user: user)

    post = insert(:published_post, user: user)

    :ok = Sanbase.FeaturedItem.update_item(post, _featured = true)

    {:ok, _} = Sanbase.Vote.create(%{user_id: user.id, post_id: post.id})

    blockchain_address =
      insert(:blockchain_address,
        infrastructure:
          Sanbase.Repo.get_by(Sanbase.Model.Infrastructure, code: "ETH") ||
            build(:infrastructure, %{code: "ETH"})
      )

    {:ok, _} =
      Sanbase.BlockchainAddress.BlockchainAddressUserPair.create(
        blockchain_address.address,
        "ETH",
        user.id
      )

    {:ok, _} = Sanbase.Accounts.Apikey.generate_apikey(user)
    {:ok, _} = Sanbase.ApiCallLimit.get_quota_db(:user, user)
    :ok = Sanbase.ApiCallLimit.update_usage(:user, user, 500, :apikey)

    {:ok, _} =
      TimelineEvent.create_changeset(%TimelineEvent{}, %{
        user_id: user.id,
        post_id: post.id,
        event_type: TimelineEvent.publish_insight_type()
      })
      |> Sanbase.Repo.insert()

    insert(:alerts_historical_activity,
      user: user,
      user_trigger: user_trigger,
      payload: %{},
      data: %{
        "user_trigger_data" => %{
          "santiment" => %{"type" => "metric_signal", "metric" => "daily_active_addresses"}
        }
      },
      triggered_at: Timex.shift(Timex.now(), days: -1)
    )

    {:ok, _} = Sanbase.Accounts.AccessAttempt.create("email_login", user, "127.0.0.1")

    {:ok, _} =
      Sanbase.PresignedS3Url.get_presigned_s3_url(
        user.id,
        "data"
      )

    %{} = Sanbase.Accounts.UserSettings.settings_for(user)

    assert {:ok, _} = Sanbase.Repo.delete(user)
  end
end
