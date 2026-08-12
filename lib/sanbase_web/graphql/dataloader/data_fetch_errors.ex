defmodule SanbaseWeb.Graphql.DataFetchErrors do
  @moduledoc ~s"""
  Soft-error channel for Dataloader batch failures.

  With `get_policy: :tuples` a failed batch fetch surfaces as `{:error, reason}`
  per requested key. Most fields degrade gracefully instead of failing the whole
  request (e.g. one failed metric on `allProjects` must not fail the request).
  This module lets resolvers record such degraded fetches so they can be
  communicated to the client via the `extensions.dataFetchErrors` key in the
  GraphQL response, injected by
  `SanbaseWeb.Graphql.Phase.Document.Result.DataFetchErrors`.

  The errors are accumulated in the process dictionary. Dataloader `on_load`
  callbacks run in the same process that executes the Absinthe document
  pipeline, so the phase that runs after the Result phase can read them.

  Recording an error also sets the `:do_not_cache_query` process flag so
  degraded responses are not stored in the document cache.
  """

  @process_dict_key :__data_fetch_errors__

  @doc ~s"""
  Record a failed data fetch for the given dataloader source key.

  Sets `:do_not_cache_query` so the degraded response is not cached by the
  CacheDocument phase/before_send hook.
  """
  @spec record(atom() | String.t(), any()) :: :ok
  def record(source, reason) do
    entry = %{source: to_string(source), reason: normalize_reason(reason)}
    Process.put(@process_dict_key, [entry | Process.get(@process_dict_key, [])])
    Process.put(:do_not_cache_query, true)

    :ok
  end

  @doc ~s"""
  Unwrap a `Dataloader.get/4` result obtained under the `:tuples` get policy.

  Returns the value on `{:ok, value}`. On `{:error, reason}` records a soft
  error for `source` and returns `nil`, so existing `value || default` logic
  in the resolvers keeps working unchanged.
  """
  @spec unwrap({:ok, any()} | {:error, any()}, atom() | String.t()) :: any()
  def unwrap({:ok, value}, _source), do: value

  def unwrap({:error, reason}, source) do
    record(source, reason)
    nil
  end

  @doc ~s"""
  Return the deduplicated list of recorded soft errors for this process.
  """
  @spec get_unique() :: [%{source: String.t(), reason: String.t()}]
  def get_unique() do
    Process.get(@process_dict_key, [])
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason), do: inspect(reason)
end
