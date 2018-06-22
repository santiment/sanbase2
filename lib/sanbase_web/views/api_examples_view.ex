defmodule SanbaseWeb.ApiExamplesView do
  use SanbaseWeb, :view
  require Logger

  def render("apiexample_view.html", _assigns) do
    Phoenix.View.render_to_string(SanbaseWeb.ApiExamplesView, "examples.html", %{
      explorer_url: explorer_url(),
      daa: %{
        query: daa(),
        variables: "{}"
      },
      burn_rate: %{
        query: burn_rate(),
        variables: "{}"
      },
      tv: %{
        query: tv(),
        variables: "{}"
      },
      ga: %{
        query: ga(),
        variables: "{}"
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
        ticker: "SAN",
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
end
