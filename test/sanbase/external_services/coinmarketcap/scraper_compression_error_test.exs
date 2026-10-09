defmodule Sanbase.ExternalServices.Coinmarketcap.ScraperCompressionErrorTest do
  @moduledoc ~s"""
  Reproduces SANBASE-BACKEND-PROD-G9V:
  Tesla.Middleware.Compression.Error: zlib error during decompression: :data_error

  coinmarketcap.com sometimes answers with `content-encoding: gzip` and a body
  that is not a complete gzip stream. Since tesla 1.20 the Compression middleware
  verifies the stream end (`:zlib.inflateEnd/1`) and raises
  `Tesla.Middleware.Compression.Error`. The ErrorCatcher middleware only rescues
  `Tesla.Error`, so the exception escapes `fetch_project_page/1` and crashes the
  CMC fetch_project_info task.
  """
  use ExUnit.Case, async: false

  alias Sanbase.ExternalServices.Coinmarketcap.Scraper

  test "a corrupt gzip body is returned as an error instead of raising" do
    truncated_gzip = binary_part(:zlib.gzip("<html>bitcoin</html>"), 0, 15)

    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        headers: [{"content-encoding", "gzip"}],
        body: truncated_gzip
      }
    end)

    assert {:error, _} = Scraper.fetch_project_page("bitcoin")
  end

  test "a non-gzip body labelled as gzip is returned as an error instead of raising" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        headers: [{"content-encoding", "gzip"}],
        body: "<html>not gzipped</html>"
      }
    end)

    assert {:error, _} = Scraper.fetch_project_page("bitcoin")
  end
end
