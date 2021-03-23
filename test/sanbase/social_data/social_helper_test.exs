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
    test "with existing slug: success" do
      assert SocialHelper.social_metrics_selector_handler(%{slug: "santiment"}) ==
               {:ok, %{slug: "santiment"}}
    end

    test "with text: success" do
      assert SocialHelper.social_metrics_selector_handler(%{text: "santiment"}) ==
               {:ok, %{text: "santiment"}}
    end

    test "with false argument" do
      assert SocialHelper.social_metrics_selector_handler("santiment") ==
               {:error, "Invalid argument please input a slug or search_text"}
    end
  end

  describe "handle_search_term" do
    test "with slug" do
      assert SocialHelper.handle_search_term(%{slug: "santiment"}) == {"slug", "santiment"}
    end

    test "with basic search text" do
      assert SocialHelper.handle_search_term(%{text: "some_basic_text"}) ==
               {"search_text", "some_basic_text"}
    end

    test "with non-uri search text" do
      original_text = "some non uri text))"

      assert {"search_text", search_text} =
               SocialHelper.handle_search_term(%{text: "some non uri text))"})

      assert search_text == URI.encode(original_text)
    end
  end
end
