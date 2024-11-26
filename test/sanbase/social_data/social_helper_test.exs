defmodule Sanbase.SocialHelperTest do
  use SanbaseWeb.ConnCase, async: false
  alias Sanbase.SocialData.SocialHelper

  describe "split_by_source/1" do
    test "splits the slug accordingly" do
      assert SocialHelper.split_by_source("sentiment_weighted_twitter") ==
               {"sentiment_weighted", "twitter"}
    end
  end

  describe "social_metrics_selector_handler/1" do
    test "with existing slug: success" do
      Sanbase.Factory.insert(:project, %{ticker: "SAN", name: "Santiment", slug: "santiment"})

      assert SocialHelper.social_metrics_selector_handler(%{slug: "santiment"}) ==
               {:ok, "search_text", ~s/"san" OR "santiment"/}
    end

    test "with text: success" do
      assert SocialHelper.social_metrics_selector_handler(%{text: "santiment"}) ==
               {:ok, "search_text", "santiment"}
    end

    test "with founders: success" do
      assert SocialHelper.social_metrics_selector_handler(%{founders: ["vitalik", "satoshi"]}) ==
               {:ok, "founders", "vitalik,satoshi"}
    end

    test "with false argument" do
      assert SocialHelper.social_metrics_selector_handler("santiment") ==
               {:error, "Invalid argument please input a slug or search_text"}
    end
  end
end
