defmodule Sanbase.Elasticsearch do
  require Sanbase.Utils.Config, as: Config
  alias Sanbase.Elasticsearch.Cluster
  alias Sanbase.Utils.Math
  @bytes_in_megabyte 1024 * 1024

  @indices Config.get(:indices)

  def stats(from, to) do
    {:ok, stats} = Elasticsearch.get(Cluster, "/#{@indices}/_stats")
    size_in_bytes = get_in(stats, ["_all", "total", "store", "size_in_bytes"])
    size_in_megabytes = (size_in_bytes / @bytes_in_megabyte) |> Math.to_integer()
    documents_count = documents_count(from, to)
    days_difference = Timex.diff(from, to, :days) |> abs()

    %{
      documents_count: documents_count,
      size_in_megabytes: size_in_megabytes,
      telegram_channels_count: telegram_channels_count(from, to),
      subreddits_count: subreddits_count(from, to),
      average_documents_per_day: (documents_count / days_difference) |> Math.to_integer()
    }
  end

  defp documents_count(from, to) do
     {:ok, data} =
      Elasticsearch.post(
        Cluster,
        "/#{@indices}/_search",
        Sanbase.Elasticsearch.Query.documents_count_in_interval(from, to)
      )

    %{"hits" => %{"total" => total}} = data
    total
  end

  defp telegram_channels_count(from, to) do
    {:ok, data} =
      Elasticsearch.post(
        Cluster,
        "/telegram/_search",
        Sanbase.Elasticsearch.Query.telegram_channels_count(from, to)
      )

    %{"aggregations" => %{"chat_titles" => %{"buckets" => buckets}}} = data
    Enum.count(buckets)
  end

  defp subreddits_count(from, to) do
    {:ok, data} =
      Elasticsearch.post(
        Cluster,
        "/reddit/_search",
        Sanbase.Elasticsearch.Query.subreddits_count(from, to)
      )

    %{"aggregations" => %{"subreddits" => %{"buckets" => buckets}}} = data
    Enum.count(buckets)
  end
end
