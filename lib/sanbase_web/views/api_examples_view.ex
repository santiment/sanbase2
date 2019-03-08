defmodule SanbaseWeb.ApiExamplesView do
  use SanbaseWeb, :view

  require Logger
  require Sanbase.Utils.Config, as: Config

  def render("apiexample_view.html", _assigns) do
    Phoenix.View.render_to_string(SanbaseWeb.ApiExamplesView, "examples.html", %{
      api_url: SanbaseWeb.Endpoint.api_url(),
      explorer_url: explorer_url(),
      required_san_stake_full_access: required_san_stake_full_access(),
      daa: %{
        query: daa(),
        variables: "{}",
        docs: docs(:daily_active_addresses)
      },
      token_age_consumed: %{
        query: token_age_consumed(),
        variables: "{}",
        docs: docs(:token_age_consumed)
      },
      tv: %{
        query: tv(),
        variables: "{}",
        docs: docs(:transaction_volume)
      },
      exchange_funds_flow: %{
        query: exchange_funds_flow(),
        variables: "{}",
        docs: docs(:exchange_funds_flow)
      },
      ga: %{
        query: ga(),
        variables: "{}",
        docs: docs(:github_activity)
      },
      erc20_exchange_funds_flow: %{
        query: erc20_exchange_funds_flow(),
        variables: "{}",
        docs: docs(:erc20_exchange_funds_flow)
      },
      social_volume: %{
        query: social_volume(),
        variables: "{}",
        docs: docs(:social_volume)
      },
      social_volume_projects: %{
        query: social_volume_projects(),
        variables: "{}",
        docs: docs(:social_volume_projects)
      },
      topic_search: %{
        query: topic_search(),
        variables: "{}",
        docs: docs(:topic_search)
      }
    })
    |> as_html()
  end

  def as_html(txt) do
    txt
    |> Earmark.as_html!()
    |> String.replace("&amp;", "&")
    |> String.replace(~r|\"&quot;|, "'")
    |> String.replace(~r|&quot;\"|, "'")
    |> String.replace("''", "'")
    |> raw()
  end

  defp daa do
    """
    query {
      dailyActiveAddresses(
        slug: "santiment",
        from: "2018-06-01 16:00:00Z",
        to: "2018-06-05 16:00:00Z",
        interval: "1d") {
          activeAddresses,
          datetime
        }
    }
    """
  end

  defp token_age_consumed do
    """
    query {
      burnRate(
        slug: "santiment",
        from: "2018-01-01 16:00:00Z",
        to: "2018-06-05 16:00:00Z",
        interval: "1h") {
          burnRate,
          datetime
        }
    }
    """
  end

  defp tv do
    """
    query {
      transactionVolume(
        slug: "santiment",
        from: "2018-01-01 16:00:00Z",
        to: "2018-06-05 16:00:00Z",
        interval: "15m") {
          transactionVolume,
          datetime
        }
    }
    """
  end

  defp ga do
    """
    query {
      githubActivity(
        slug: "santiment",
        from: "2018-06-13 16:00:00Z",
        to: "2018-07-13 16:00:00Z"
        interval: "24h") {
          activity
        }
    }
    """
  end

  defp erc20_exchange_funds_flow do
    """
    query {
      erc20ExchangeFundsFlow(
        from: "2018-04-16T10:02:19Z",
        to: "2018-05-23T10:02:19Z") {
          ticker,
          contract,
          exchangeIn,
          exchangeOut,
          exchangeDiff,
          exchangeInUsd,
          exchangeOutUsd,
          exchangeDiffUsd,
          percentDiffExchangeDiffUsd,
          exchangeVolumeUsd,
          percentDiffExchangeVolumeUsd,
          exchangeInBtc,
          exchangeOutBtc,
          exchangeDiffBtc,
          percentDiffExchangeDiffBtc,
          exchangeVolumeBtc,
          percentDiffExchangeVolumeBtc
        }
    }
    """
  end

  defp social_volume do
    """
    query {
      socialVolume(
        slug: "dragonchain",
        from: "2018-04-16T10:02:19Z",
        to: "2018-05-23T10:02:19Z",
        interval:"1h",
        socialVolumeType: TELEGRAM_DISCUSSION_OVERVIEW
        ) {
          mentionsCount,
          datetime
        }
    }
    """
  end

  defp social_volume_projects do
    """
    query {
      socialVolumeProjects
    }
    """
  end

  defp topic_search do
    """
    query {
      topicSearch(
        source: TELEGRAM,
        searchText: "btc moon",
        from: "2018-08-01T12:00:00Z",
        to: "2018-08-15T12:00:00Z",
        interval: "6h"
      ) {
        messages {
          datetime
          text
        }
        chartData {
          mentionsCount
          datetime
        }
      }
    }
    """
  end

  defp exchange_funds_flow do
    """
    query {
      exchangeFundsFlow(
        slug: "santiment",
        from: "2018-01-01 16:00:00Z",
        to: "2018-06-05 16:00:00Z",
        interval: "6h") {
          datetime
          inOutDifference
        }
      )
    }
    """
  end

  defp explorer_url() do
    SanbaseWeb.Endpoint.backend_url() <> "/graphiql"
  end

  def docs(field) do
    Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query).fields
    |> Map.get(field)
    |> Map.get(:description)
  end

  defp required_san_stake_full_access() do
    Config.module_get(Sanbase, :required_san_stake_full_access)
    |> String.to_integer()
  end
end
