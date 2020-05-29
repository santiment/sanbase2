defmodule Sanbase.Elasticsearch do
  @moduledoc ~s"""
  Module providing API to Santiment's managed elasticsearch instance.
  """

  @type stats :: %{
          documents_count: non_neg_integer,
          size_in_megabytes: non_neg_integer,
          telegram_channels_count: non_neg_integer,
          subreddits_count: non_neg_integer,
          discord_channels_count: non_neg_integer,
          average_documents_per_day: non_neg_integer
        }

  require Sanbase.Utils.Config, as: Config
  alias Sanbase.Elasticsearch.Cluster
  alias Sanbase.Math

  @bytes_in_megabyte 1024 * 1024
  @indices Config.get(:indices)

  @doc ~s"""
  Provides statistics for a predefined indices, displayed on sanbase.
  """
  @spec stats(%DateTime{}, %DateTime{}) :: stats
  def stats(%DateTime{} = from, %DateTime{} = to) do
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
      discord_channels_count: discord_channels_count(from, to),
      average_documents_per_day: (documents_count / days_difference) |> Math.to_integer()
    }
  end

  # Private functions

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

  defp discord_channels_count(from, to) do
    {:ok, data} =
      Elasticsearch.post(
        Cluster,
        "/discord/_search",
        Sanbase.Elasticsearch.Query.discord_channels_count(from, to)
      )

    %{"aggregations" => %{"channel_names" => %{"buckets" => buckets}}} = data
    Enum.count(buckets)
  end
end
