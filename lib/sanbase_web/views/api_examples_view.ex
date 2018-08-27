defmodule SanbaseWeb.ApiExamplesView do
  use SanbaseWeb, :view

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias SanbaseWeb.Graphql.Middlewares.ApiTimeframeRestriction

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
      burn_rate: %{
        query: burn_rate(),
        variables: "{}",
        docs: docs(:burn_rate)
      },
      tv: %{
        query: tv(),
        variables: "{}",
        docs: docs(:transaction_volume)
      },
      ga: %{
        query: ga(),
        variables: "{}",
        docs: docs(:github_activity)
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

  defp burn_rate do
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
        from: "2017-06-13 16:00:00Z",
        interval: "24h") {
          activity
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
        sources: [TELEGRAM, PROFESSIONAL_TRADERS_CHAT, REDDIT],
        searchText: "btc moon",
        from: "2018-08-01T12:00:00Z",
        to: "2018-08-15T12:00:00Z",
        interval: "6h"
      ) {
        messages {
          telegram {
            datetime
            text
          }
          professionalTradersChat {
            datetime
            text
          }
          reddit {
            datetime
            text
          }
        }
        chartsData {
          telegram {
            mentionsCount
            datetime
          }
          professionalTradersChat {
            mentionsCount
            datetime
          }
          reddit {
            mentionsCount
            datetime
          }
        }
      }
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
    Config.module_get(ApiTimeframeRestriction, :required_san_stake_full_access)
    |> String.to_integer()
  end
end
