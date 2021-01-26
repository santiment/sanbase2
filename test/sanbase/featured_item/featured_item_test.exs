defmodule Sanbase.FeaturedItemTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.FeaturedItem
  alias Sanbase.Insight.Post

  describe "chart configuration featured items" do
    test "no chart configurations are featured" do
      assert FeaturedItem.chart_configurations() == []
    end

    test "cannot make private chart configuration featured" do
      chart_config = insert(:chart_configuration, is_public: false)
      {:error, error_msg} = FeaturedItem.update_item(chart_config, true)
      assert error_msg =~ "cannot be made featured"
    end

    test "marking chart configurations as featured" do
      chart_config = insert(:chart_configuration, is_public: true)

      :ok = FeaturedItem.update_item(chart_config, true)
      [featured_chart_config] = FeaturedItem.chart_configurations()

      assert featured_chart_config.id == chart_config.id
    end

    test "unmarking chart configurations as featured" do
      chart_config = insert(:chart_configuration, is_public: true)

      :ok = FeaturedItem.update_item(chart_config, true)
      :ok = FeaturedItem.update_item(chart_config, false)
      assert FeaturedItem.chart_configurations() == []
    end

    test "marking chart configuration as featured is idempotent" do
      chart_config = insert(:chart_configuration, is_public: true)

      :ok = FeaturedItem.update_item(chart_config, true)
      :ok = FeaturedItem.update_item(chart_config, true)
      :ok = FeaturedItem.update_item(chart_config, true)
      [featured_chart_config] = FeaturedItem.chart_configurations()
      assert featured_chart_config.id == chart_config.id
    end
  end

  describe "table configuration featured items" do
    test "no table configurations are featured" do
      assert FeaturedItem.table_configurations() == []
    end

    test "cannot make private table configuration featured" do
      table_config = insert(:table_configuration, is_public: false)
      {:error, error_msg} = FeaturedItem.update_item(table_config, true)
      assert error_msg =~ "cannot be made featured"
    end

    test "marking table configurations as featured" do
      table_config = insert(:table_configuration, is_public: true)

      :ok = FeaturedItem.update_item(table_config, true)
      [featured_table_config] = FeaturedItem.table_configurations()

      assert featured_table_config.id == table_config.id
    end

    test "unmarking table configurations as featured" do
      table_config = insert(:table_configuration, is_public: true)

      :ok = FeaturedItem.update_item(table_config, true)
      :ok = FeaturedItem.update_item(table_config, false)
      assert FeaturedItem.table_configurations() == []
    end

    test "marking table configuration as featured is idempotent" do
      table_config = insert(:table_configuration, is_public: true)

      :ok = FeaturedItem.update_item(table_config, true)
      :ok = FeaturedItem.update_item(table_config, true)
      :ok = FeaturedItem.update_item(table_config, true)
      [featured_table_config] = FeaturedItem.table_configurations()
      assert featured_table_config.id == table_config.id
    end
  end

  describe "insight featured items" do
    test "no insights are featured" do
      assert FeaturedItem.insights() == []
    end

    test "cannot make not published insights featured" do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.draft())
      {:error, error_msg} = FeaturedItem.update_item(insight, true)
      assert error_msg =~ "cannot be made featured"
    end

    test "marking insights as featured" do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      :ok = FeaturedItem.update_item(insight, true)
      [featured_insight] = FeaturedItem.insights()

      assert featured_insight.id == insight.id
    end

    test "unmarking insights as featured" do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      :ok = FeaturedItem.update_item(insight, true)
      :ok = FeaturedItem.update_item(insight, false)
      assert FeaturedItem.insights() == []
    end

    test "marking insight as featured is idempotent" do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())

      :ok = FeaturedItem.update_item(insight, true)
      :ok = FeaturedItem.update_item(insight, true)
      :ok = FeaturedItem.update_item(insight, true)
      [featured_insight] = FeaturedItem.insights()
      assert featured_insight.id == insight.id
    end
  end

  describe "watchlist featured items" do
    test "no watchlists are featured" do
      assert FeaturedItem.watchlists(:project) == []
    end

    test "cannot make private watchlist featured" do
      watchlist = insert(:watchlist, is_public: false)
      {:error, error_msg} = FeaturedItem.update_item(watchlist, true)
      assert error_msg =~ "cannot be made featured"
    end

    test "marking watchlists as featured" do
      watchlist =
        insert(:watchlist, is_public: true, type: :blockchain_address)
        |> Sanbase.Repo.preload([:list_items])

      insert(:watchlist, is_public: true, type: :project)
      :ok = FeaturedItem.update_item(watchlist, true)
      assert FeaturedItem.watchlists(:blockchain_address) == [watchlist]
    end

    test "unmarking watchlists as featured" do
      watchlist = insert(:watchlist, is_public: true, type: :blockchain_address)
      _ = insert(:watchlist, is_public: true, type: :blockchain_address)
      _ = insert(:watchlist, is_public: true)

      FeaturedItem.update_item(watchlist, true)
      FeaturedItem.update_item(watchlist, false)

      assert FeaturedItem.watchlists(:blockchain_address) == []
    end

    test "marking watchlist as featured is idempotent" do
      watchlist = insert(:watchlist, is_public: true) |> Sanbase.Repo.preload([:list_items])
      :ok = FeaturedItem.update_item(watchlist, true)
      :ok = FeaturedItem.update_item(watchlist, true)
      :ok = FeaturedItem.update_item(watchlist, true)

      assert FeaturedItem.watchlists() == [watchlist]
    end
  end

  describe "user_trigger featured items" do
    test "no user_triggers are featured" do
      assert FeaturedItem.user_triggers() == []
    end

    test "cannot make private user_trigger featured" do
      user_trigger = insert(:user_trigger, is_public: false)
      {:error, error_msg} = FeaturedItem.update_item(user_trigger, true)
      assert error_msg =~ "cannot be made featured"
    end

    test "marking user_triggers as featured" do
      user_trigger = insert(:user_trigger, is_public: true) |> Sanbase.Repo.preload([:tags])
      :ok = FeaturedItem.update_item(user_trigger, true)
      assert FeaturedItem.user_triggers() == [user_trigger]
    end

    test "unmarking user_triggers as featured" do
      user_trigger = insert(:user_trigger, is_public: true)
      :ok = FeaturedItem.update_item(user_trigger, true)
      :ok = FeaturedItem.update_item(user_trigger, false)
      assert FeaturedItem.user_triggers() == []
    end

    test "marking user_trigger as featured is idempotent" do
      user_trigger =
        insert(:user_trigger, is_public: true)
        |> Sanbase.Repo.preload([:tags])

      :ok = FeaturedItem.update_item(user_trigger, true)
      :ok = FeaturedItem.update_item(user_trigger, true)
      :ok = FeaturedItem.update_item(user_trigger, true)

      assert FeaturedItem.user_triggers() == [user_trigger]
    end
  end
end
