defmodule Sanbase.Kafka.ApiCall do
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

  @spec json_kv_tuple(api_call_data | [api_call_data]) :: [json_kv_tuple]
  @doc ~s"""
  Returns a list of tuples of json encoded strings representing key and value to be
  saved in kafka. Key here is "" since it is required by Kaffe producer but we are not using it.
  """
  def json_kv_tuple(api_call_data) do
    api_call_data
    |> List.wrap()
    |> Enum.map(&{:erlang.phash2(api_call_data), Jason.encode!(&1)})
  end
end
