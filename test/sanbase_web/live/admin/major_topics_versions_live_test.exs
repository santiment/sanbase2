defmodule SanbaseWeb.Admin.MajorTopicsVersionsLiveTest do
  # Mocks ClickhouseRepo globally, so it cannot run async
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.Factory
  import Sanbase.MajorTopicsClickhouseMock, only: [with_clickhouse: 2]

  alias Sanbase.MajorTopics
  alias Sanbase.MajorTopics.TopicBatch

  @interval "2026-09-11T00:00:00/2026-09-18T00:00:00"

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload_v1())

    {:ok, batch} =
      MajorTopics.publish_batch(batch, user.id, TopicBatch.daily_weekly_scope())

    {:ok, conn: conn, batch: batch}
  end

  test "refetches a newer version and moves the batch back to draft", %{
    conn: conn,
    batch: batch
  } do
    with_clickhouse(%{@interval => 2}, fn ->
      {:ok, view, _html} = live(conn, "/admin/major_topics/#{batch.id}")
      render_async(view)

      assert has_element?(view, "#newer-version", "v2 available")

      view |> element("#refetch-new-version") |> render_click()
      render_async(view)

      refetched = MajorTopics.get_batch!(batch.id)
      assert refetched.version == 2
      assert refetched.state == "draft"
      assert Enum.map(refetched.topics, & &1.label) == ["v2 topic 0", "v2 topic 1"]

      refute has_element?(view, "#refetch-new-version")
      assert has_element?(view, "#publish-daily-weekly")
    end)
  end

  test "hides the refetch button when ClickHouse has no newer version", %{
    conn: conn,
    batch: batch
  } do
    with_clickhouse(%{@interval => 1}, fn ->
      {:ok, view, _html} = live(conn, "/admin/major_topics/#{batch.id}")
      render_async(view)

      refute has_element?(view, "#refetch-new-version")
    end)
  end

  test "marks batches with a newer version in the list", %{conn: conn, batch: batch} do
    with_clickhouse(%{@interval => 2}, fn ->
      {:ok, view, _html} = live(conn, "/admin/major_topics")
      render_async(view)

      assert has_element?(view, "#newer-version-#{batch.id}", "v2 available")
    end)
  end

  defp payload_v1 do
    %{
      source: "twitter_crypto",
      version: 1,
      interval: @interval,
      topics:
        Enum.map(0..1, fn idx ->
          %{
            ch_id: "1;#{idx};twitter_crypto;#{@interval};bertopic",
            topic_id: idx,
            title: "v1 topic #{idx}",
            summary: "Summary #{idx}.",
            top_words: "word#{idx}",
            is_crypto_relevant: true,
            type: "bertopic",
            values: [%{dt: ~U[2026-09-11 00:00:00Z], value: 1.0}]
          }
        end)
    }
  end
end
