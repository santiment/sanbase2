defmodule Sanbase.SocialData.DecodeErrorTest do
  use Sanbase.DataCase, async: false

  import Mockery
  import Sanbase.Factory

  alias Sanbase.SocialData

  @from ~U[2019-01-01 00:00:00Z]
  @to ~U[2019-01-03 00:00:00Z]

  @moduletag capture_log: true

  setup do
    insert(:project, slug: "santiment", ticker: "SAN")

    mock(
      HTTPoison,
      :get,
      {:ok, %HTTPoison.Response{status_code: 200, body: "<html>not json</html>"}}
    )

    :ok
  end

  test "sentiment returns an error when the response is not JSON" do
    assert {:error, _} =
             SocialData.Sentiment.sentiment(
               %{slug: "santiment"},
               @from,
               @to,
               "1d",
               "telegram",
               "positive"
             )
  end

  test "social dominance returns an error when the response is not JSON" do
    assert {:error, _} =
             SocialData.SocialDominance.social_dominance(
               %{slug: "santiment"},
               @from,
               @to,
               "1d",
               :telegram
             )
  end

  test "social active users returns an error when the response is not JSON" do
    assert {:error, _} =
             SocialData.ActiveUsers.social_active_users(
               %{source: "telegram"},
               @from,
               @to,
               "1d"
             )
  end

  test "word context returns an error when the response is not JSON" do
    assert {:error, _} = SocialData.word_context("merry", :telegram, 3, @from, @to)
  end
end
