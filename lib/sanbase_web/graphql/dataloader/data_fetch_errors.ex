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

  `key` is the key the failed value was fetched under (a slug, an id, a
  selector) — pass whatever was given to `Dataloader.get/4` so the client can
  tell which entities degraded. The keys are aggregated per unique
  `{source, reason, extras}` combination by `get_unique/0`.

  `extra` is a keyword list of optional entry fields:

    - `:field` — the GraphQL response field the degraded value would have
      appeared under: the field's alias if the query used one, otherwise the
      field name (`resolution.definition.alias || resolution.definition.name`).
      Lets clients map the error to the exact response field when the same
      field is queried multiple times under different aliases.
    - `:metric` — the metric name, for sources that fetch a metric.

  Sets `:do_not_cache_query` so the degraded response is not cached by the
  CacheDocument phase/before_send hook.
  """
  @spec record(atom() | String.t(), any(), any(), Keyword.t()) :: :ok
  def record(source, reason, key \\ nil, extra \\ []) do
    entry =
      %{
        source: to_string(source),
        reason: normalize_reason(reason),
        key: normalize_key(key)
      }
      |> maybe_put(:field, extra[:field])
      |> maybe_put(:metric, extra[:metric])

    Process.put(@process_dict_key, [entry | Process.get(@process_dict_key, [])])
    Process.put(:do_not_cache_query, true)

    :ok
  end

  @doc ~s"""
  Unwrap a `Dataloader.get/4` result obtained under the `:tuples` get policy.

  Returns the value on `{:ok, value}`. On `{:error, reason}` records a soft
  error for `source` under `key` (with the optional `extra` fields — see
  `record/4`) and returns `nil`, so existing `value || default` logic in the
  resolvers keeps working unchanged.
  """
  @spec unwrap({:ok, any()} | {:error, any()}, atom() | String.t(), any(), Keyword.t()) ::
          any()
  def unwrap(result, source, key \\ nil, extra \\ [])

  def unwrap({:ok, value}, _source, _key, _extra), do: value

  def unwrap({:error, reason}, source, key, extra) do
    record(source, reason, key, extra)
    nil
  end

  @doc ~s"""
  Return the recorded soft errors, one entry per unique combination of all
  entry fields except `:key` (source, reason and the optional extras), each
  with the deduplicated list of keys that failed with that combination.

  The extra keys (`:field`, `:metric`) are present only in entries recorded
  with them.
  """
  @spec get_unique() :: [
          %{
            required(:source) => String.t(),
            required(:reason) => String.t(),
            required(:keys) => [any()],
            optional(:field) => String.t(),
            optional(:metric) => String.t()
          }
        ]
  def get_unique() do
    entries = Process.get(@process_dict_key, []) |> Enum.reverse()

    entries
    |> Enum.map(&Map.delete(&1, :key))
    |> Enum.uniq()
    |> Enum.map(fn group ->
      keys =
        for entry <- entries,
            Map.delete(entry, :key) == group,
            not is_nil(entry.key),
            do: entry.key

      Map.put(group, :keys, Enum.uniq(keys))
    end)
  end

  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason), do: inspect(reason)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Keys end up in the JSON response — tuples and other non-JSON-encodable
  # terms are inspected.
  defp normalize_key(key) when is_nil(key) or is_binary(key) or is_atom(key) or is_number(key),
    do: key

  defp normalize_key(key), do: inspect(key)
end
