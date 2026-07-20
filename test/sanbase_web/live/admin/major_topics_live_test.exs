defmodule SanbaseWeb.Admin.MajorTopicsLiveTest do
  use SanbaseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.MajorTopics
  alias Sanbase.MajorTopics.TopicBatch

  @daily_only_scope TopicBatch.daily_only_scope()
  @weekly_only_scope TopicBatch.weekly_only_scope()
  @daily_weekly_scope TopicBatch.daily_weekly_scope()

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    {:ok, batch} = MajorTopics.upsert_batch_from_payload(sample_payload())

    {:ok, conn: conn, batch: batch}
  end

  test "publishes a batch for daily views only", %{conn: conn, batch: batch} do
    {:ok, view, _html} = live(conn, "/admin/major_topics/#{batch.id}")

    assert has_element?(
             view,
             "#publish-daily-only[phx-value-scope='#{@daily_only_scope}']"
           )

    view
    |> element("#publish-daily-only")
    |> render_click()

    published = MajorTopics.get_batch!(batch.id)
    assert published.state == "published"
    assert published.publication_scope == @daily_only_scope
    assert has_element?(view, "#publication-scope", "Live: Daily only")
  end

  test "publishes a batch for daily and weekly views", %{conn: conn, batch: batch} do
    {:ok, view, _html} = live(conn, "/admin/major_topics/#{batch.id}")

    assert has_element?(
             view,
             "#publish-daily-weekly[phx-value-scope='#{@daily_weekly_scope}']"
           )

    view
    |> element("#publish-daily-weekly")
    |> render_click()

    published = MajorTopics.get_batch!(batch.id)
    assert published.state == "published"
    assert published.publication_scope == @daily_weekly_scope
    assert has_element?(view, "#publication-scope", "Live: Daily + weekly")
  end

  test "warns but allows daily and weekly publication below 20 active topics", %{
    conn: conn,
    batch: batch
  } do
    {:ok, view, _html} = live(conn, "/admin/major_topics/#{batch.id}")

    assert has_element?(view, "#daily-weekly-topic-warning")

    assert has_element?(
             view,
             "#publish-daily-weekly[data-confirm*='Only 2 active topics remain']"
           )

    view
    |> element("#publish-daily-weekly")
    |> render_click()

    assert MajorTopics.get_batch!(batch.id).publication_scope == @daily_weekly_scope
  end

  test "shows historical weekly-only scope in the batch list", %{conn: conn, batch: batch} do
    {:ok, _published} =
      batch
      |> Ecto.Changeset.change(
        state: "published",
        publication_scope: @weekly_only_scope,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Sanbase.Repo.update()

    {:ok, view, _html} = live(conn, "/admin/major_topics")

    assert has_element?(view, "table", "Weekly only")
  end

  defp sample_payload do
    interval = "2026-05-04T00:00:00/2026-05-11T00:00:00"

    topics =
      Enum.map(0..1, fn idx ->
        %{
          ch_id: "1;#{idx};twitter_crypto;#{interval};bertopic",
          topic_id: idx,
          title: "Topic #{idx}",
          summary: "Summary #{idx}.",
          top_words: "word#{idx}",
          is_crypto_relevant: true,
          type: "bertopic",
          values: [%{dt: ~U[2026-05-04 00:00:00Z], value: idx * 1.0}]
        }
      end)

    %{
      source: "twitter_crypto",
      version: 1,
      interval: interval,
      topics: topics
    }
  end
end
