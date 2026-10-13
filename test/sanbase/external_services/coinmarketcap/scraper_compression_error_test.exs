defmodule Sanbase.ExternalServices.Coinmarketcap.ScraperCompressionErrorTest do
  # Tesla.Middleware.Compression.Error escaped the scraper
  use ExUnit.Case,
    async: false,
    parameterize: [
      # A truncated gzip body
      %{body: binary_part(:zlib.gzip("<html>bitcoin</html>"), 0, 15)},
      # A non-gzip body labelled as gzip
      %{body: "<html>not gzipped</html>"}
    ]

  alias Sanbase.ExternalServices.Coinmarketcap.Scraper

  @moduletag capture_log: true

  test "a corrupt gzip body is returned as an error instead of raising", %{body: body} do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, headers: [{"content-encoding", "gzip"}], body: body}
    end)

    assert {:error, _} = Scraper.fetch_project_page("bitcoin")
  end
end
