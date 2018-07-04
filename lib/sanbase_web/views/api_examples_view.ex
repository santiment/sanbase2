defmodule SanbaseWeb.ApiExamplesView do
  use SanbaseWeb, :view

  require Logger
  require Sanbase.Utils.Config

  alias Sanbase.Utils.Config
  alias SanbaseWeb.Graphql.Middlewares.ApiDelay

  def render("apiexample_view.html", _assigns) do
    Phoenix.View.render_to_string(SanbaseWeb.ApiExamplesView, "examples.html", %{
      api_url: SanbaseWeb.Endpoint.api_url(),
      explorer_url: explorer_url(),
      required_san_stake_realtime_api: required_san_stake_realtime_api(),
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

  defp explorer_url() do
    SanbaseWeb.Endpoint.website_url() <> "/apiexplorer"
  end

  def docs(field) do
    Absinthe.Schema.lookup_type(SanbaseWeb.Graphql.Schema, :query).fields
    |> Map.get(field)
    |> Map.get(:description)
  end

  defp required_san_stake_realtime_api() do
    Config.module_get(ApiDelay, :required_san_stake_realtime_api) |> String.to_integer()
  end
end
