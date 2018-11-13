defmodule Sanbase.ElasticsearchMock do
  @behaviour Elasticsearch.API

  @impl true
  def request(_config, :get, "/index1,index2,index3,index4/_stats", _data, _opts) do
    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body: %{"_all" => %{"total" => %{"store" => %{"size_in_bytes" => 5_000_000}}}}
     }}
  end

  @impl true
  def request(_config, :post, "/index1,index2,index3,index4/_search", _data, _opts) do
    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body: %{"hits" => %{"total" => 1_000_000}}
     }}
  end

  @impl true
  def request(_config, :post, "/telegram/_search", _data, _opts) do
    # Buckets must be an Enumerable
    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body: %{"aggregations" => %{"chat_titles" => %{"buckets" => [1, 2, 3, 4, 5]}}}
     }}
  end

  @impl true
  def request(_config, :post, "/reddit/_search", _data, _opts) do
    # Buckets must be an Enumerable
    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body: %{
         "aggregations" => %{"subreddits" => %{"buckets" => [2, 4, 5, 6, 7, 8, 9, 0, 12, 2]}}
       }
     }}
  end

  @impl true
  def request(_config, :post, "/discord/_search", _data, _opts) do
    # Buckets must be an Enumerable
    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body: %{"aggregations" => %{"channel_names" => %{"buckets" => [1, 2, 3, 4, 5, 6]}}}
     }}
  end
end
