defmodule Sanbase.ExternalServices.Coinmarketcap.ScraperCompressionErrorTest do
  # SANBASE-BACKEND-PROD-G9V: Tesla.Middleware.Compression.Error escaped the scraper
  use ExUnit.Case, async: false

  alias Sanbase.ExternalServices.Coinmarketcap.Scraper

  for {name, body} <- [
        {"a truncated gzip body", binary_part(:zlib.gzip("<html>bitcoin</html>"), 0, 15)},
        {"a non-gzip body labelled as gzip", "<html>not gzipped</html>"}
      ] do
    @body body

    test "#{name} is returned as an error instead of raising" do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, headers: [{"content-encoding", "gzip"}], body: @body}
      end)

      assert {:error, _} = Scraper.fetch_project_page("bitcoin")
    end
  end
end
