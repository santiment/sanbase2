defmodule Sanbase.Elasticsearch do
  alias Sanbase.Elasticsearch.Cluster
  alias Sanbase.Utils.Math
  @bytes_in_megabyte 1024 * 1024

  def stats() do
    {:ok, stats} = Elasticsearch.get(Cluster, "_stats")

    size_in_bytes = get_in(stats, ["_all", "total", "store", "size_in_bytes"])
    size_in_megabytes = (size_in_bytes / @bytes_in_megabyte) |> Math.to_integer()

    %{
      documents_count: get_in(stats, ["_all", "total", "docs", "count"]),
      size_in_megabytes: size_in_megabytes,
      telegram_channels_count: telegram_channels_count(),
      subreddits_count: subreddits_count(),
      average_documents_per_day: average_documents_per_day() |> Math.to_integer()
    }
  end

  defp telegram_channels_count() do
    {:ok, stats} = Elasticsearch.get(Cluster, "/telegram/_stats")
    get_in(stats, ["_all", "total", "docs", "count"])
  end

  defp subreddits_count() do
    0
  end

  defp average_documents_per_day() do
    0
  end
end
