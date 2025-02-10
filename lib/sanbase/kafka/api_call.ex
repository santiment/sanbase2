defmodule Sanbase.Kafka.ApiCall do
  @moduledoc false
  @typedoc ~s"""
  A map that represents the API call data that will be persisted.
  """
  @type api_call_data :: %{
          timestamp: non_neg_integer() | nil,
          id: String.t(),
          query: String.t() | nil,
          status_code: non_neg_integer(),
          has_graphql_errors: boolean() | nil,
          user_id: non_neg_integer() | nil,
          auth_method: :atom | nil,
          api_token: String.t() | nil,
          remote_ip: String.t(),
          user_agent: String.t(),
          duration_ms: non_neg_integer() | nil,
          san_tokens: float() | nil
        }

  @type json_kv_tuple :: {String.t(), String.t()}

  @spec json_kv_tuple_no_hash_collision(api_call_data | [api_call_data]) :: [json_kv_tuple]
  @doc ~s"""
  Returns a list of tuples of json encoded strings representing key and value to be
  saved in kafka. The key is the hash of the element, adding an index value to create different
  keys for the same elements. This can happen when batching requests in a single graphql document.
  """
  def json_kv_tuple_no_hash_collision(api_call_data) do
    api_call_data
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.map(fn {elem, index} ->
      {Sanbase.Cache.hash({elem, index}), Jason.encode!(elem)}
    end)
  end

  @spec json_kv_tuple(api_call_data | [api_call_data]) :: [json_kv_tuple]
  @doc ~s"""
  Returns a list of tuples of json encoded strings representing key and value to be
  saved in kafka.
  """
  def json_kv_tuple(api_call_data) do
    api_call_data
    |> List.wrap()
    |> Enum.map(&{Sanbase.Cache.hash(&1), Jason.encode!(&1)})
  end
end
