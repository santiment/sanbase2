defmodule Sanbase.SocialHelperTest do
  use SanbaseWeb.ConnCase, async: false
  alias Sanbase.SocialData.SocialHelper

  describe "split_by_source/1" do
    test "splits the slug accordingly" do
      assert SocialHelper.split_by_source("volume_consumed_twitter") ==
               {"volume_consumed", "twitter"}
    end
  end

  describe "social_metrics_selector_handler/1" do
    alias Sanbase.Model.Project

    test "with existing slug: success" do
      _project = Sanbase.Factory.insert(%Project{name: "santiment", slug: "santiment"})

      assert SocialHelper.social_metrics_selector_handler(%{slug: "santiment"}) ==
               {:ok, "\"santiment\" OR \"santiment\""}
    end

    test "with text: success" do
      assert SocialHelper.social_metrics_selector_handler(%{text: "santiment"}) ==
               {:ok, "santiment"}
    end

    test "with false argument" do
      assert SocialHelper.social_metrics_selector_handler("santiment") ==
               {:error, "Invalid argument please input a slug or search_text"}
    end
  end
end
