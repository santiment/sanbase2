defmodule Sanbase.SentimentTest do
  use SanbaseWeb.ConnCase, async: false
  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.SocialData.Sentiment
  import Sanbase.Factory

  setup do
    project =
      insert(:project, %{
        slug: "santiment",
        ticker: "SAN",
        main_contract_address: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"
      })

    [
      project: project
    ]
  end

  describe "sentiment_positive/5" do
    test "response with slug: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 5, \"2018-04-16T12:00:00Z\": 15}}",
           status_code: 200
         }}
      )

      result = Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "positive")

      assert result ==
               {:ok,
                [
                  %{value: 5, datetime: from},
                  %{value: 15, datetime: to}
                ]}
    end

    test "response with slug: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "positive")
             end) =~
               "Error status 404 fetching sentiment positive for %{slug: \"santiment\"}\n"
    end

    test "response with slug: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "positive")
             end) =~
               "Cannot fetch sentiment positive data for %{slug: \"santiment\"}: :econnrefused\n"
    end

    test "response with text: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 1, \"2018-04-16T12:00:00Z\": 0}}",
           status_code: 200
         }}
      )

      result = Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :telegram, "positive")

      assert result ==
               {:ok,
                [
                  %{datetime: from, value: 1},
                  %{datetime: to, value: 0}
                ]}
    end

    test "response with text: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :reddit, "positive")
             end) =~
               "Error status 404 fetching sentiment positive for %{text: \"btc moon\"}\n"
    end

    test "response with text: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :discord, "positive")
             end) =~
               "Cannot fetch sentiment positive data for %{text: \"btc moon\"}: :econnrefused\n"
    end
  end

  describe "sentiment_negative/5" do
    test "response with slug: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 5, \"2018-04-16T12:00:00Z\": 15}}",
           status_code: 200
         }}
      )

      result = Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "negative")

      assert result ==
               {:ok,
                [
                  %{value: 5, datetime: from},
                  %{value: 15, datetime: to}
                ]}
    end

    test "response with slug: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "negative")
             end) =~
               "Error status 404 fetching sentiment negative for %{slug: \"santiment\"}\n"
    end

    test "response with slug: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "negative")
             end) =~
               "Cannot fetch sentiment negative data for %{slug: \"santiment\"}: :econnrefused\n"
    end

    test "response with text: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 1, \"2018-04-16T12:00:00Z\": 0}}",
           status_code: 200
         }}
      )

      result = Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :telegram, "negative")

      assert result ==
               {:ok,
                [
                  %{datetime: from, value: 1},
                  %{datetime: to, value: 0}
                ]}
    end

    test "response with text: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :reddit, "negative")
             end) =~
               "Error status 404 fetching sentiment negative for %{text: \"btc moon\"}\n"
    end

    test "response with text: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :discord, "negative")
             end) =~
               "Cannot fetch sentiment negative data for %{text: \"btc moon\"}: :econnrefused\n"
    end
  end

  describe "sentiment_balance/5" do
    test "response with slug: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 5, \"2018-04-16T12:00:00Z\": 15}}",
           status_code: 200
         }}
      )

      result = Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "balance")

      assert result ==
               {:ok,
                [
                  %{value: 5, datetime: from},
                  %{value: 15, datetime: to}
                ]}
    end

    test "response with slug: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "balance")
             end) =~
               "Error status 404 fetching sentiment balance for %{slug: \"santiment\"}\n"
    end

    test "response with slug: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "balance")
             end) =~
               "Cannot fetch sentiment balance data for %{slug: \"santiment\"}: :econnrefused\n"
    end

    test "response with text: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 1, \"2018-04-16T12:00:00Z\": 0}}",
           status_code: 200
         }}
      )

      result = Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :telegram, "balance")

      assert result ==
               {:ok,
                [
                  %{datetime: from, value: 1},
                  %{datetime: to, value: 0}
                ]}
    end

    test "response with text: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :reddit, "balance")
             end) =~
               "Error status 404 fetching sentiment balance for %{text: \"btc moon\"}\n"
    end

    test "response with text: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :discord, "balance")
             end) =~
               "Cannot fetch sentiment balance data for %{text: \"btc moon\"}: :econnrefused\n"
    end
  end

  describe "sentiment_volume_consumed/5" do
    test "response with slug: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 5, \"2018-04-16T12:00:00Z\": 15}}",
           status_code: 200
         }}
      )

      result =
        Sentiment.sentiment(%{slug: "santiment"}, from, to, "1h", :telegram, "volume_consumed")

      assert result ==
               {:ok,
                [
                  %{value: 5, datetime: from},
                  %{value: 15, datetime: to}
                ]}
    end

    test "response with slug: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(
                 %{slug: "santiment"},
                 from,
                 to,
                 "1h",
                 :telegram,
                 "volume_consumed"
               )
             end) =~
               "Error status 404 fetching sentiment volume_consumed for %{slug: \"santiment\"}\n"
    end

    test "response with slug: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(
                 %{slug: "santiment"},
                 from,
                 to,
                 "1h",
                 :telegram,
                 "volume_consumed"
               )
             end) =~
               "Cannot fetch sentiment volume_consumed data for %{slug: \"santiment\"}: :econnrefused\n"
    end

    test "response with text: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 1, \"2018-04-16T12:00:00Z\": 0}}",
           status_code: 200
         }}
      )

      result =
        Sentiment.sentiment(%{text: "btc moon"}, from, to, "6h", :telegram, "volume_consumed")

      assert result ==
               {:ok,
                [
                  %{datetime: from, value: 1},
                  %{datetime: to, value: 0}
                ]}
    end

    test "response with text: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               Sentiment.sentiment(
                 %{text: "btc moon"},
                 from,
                 to,
                 "6h",
                 :reddit,
                 "volume_consumed"
               )
             end) =~
               "Error status 404 fetching sentiment volume_consumed for %{text: \"btc moon\"}\n"
    end

    test "response with text: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               Sentiment.sentiment(
                 %{text: "btc moon"},
                 from,
                 to,
                 "6h",
                 :discord,
                 "volume_consumed"
               )
             end) =~
               "Cannot fetch sentiment volume_consumed data for %{text: \"btc moon\"}: :econnrefused\n"
    end
  end
end
