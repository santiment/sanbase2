defmodule SanbaseWeb.Graphql.CacheProvider do
  @moduledoc """
  Behaviour that the cache needs to conform to.
  """

  @type hash :: String.t()
  @type key :: hash | {atom, hash}
  @type error :: String.t()
  @type stored_value :: any()
  @type cache :: atom()
  @type size_type :: :megabytes
  @doc ~s"""
  Get the value for the given key from the cache
  """
  @callback get(cache, hash) :: {:ok, any} | {:error, error} | nil

  @doc ~s"""
  Put a query document in the cache with the key as cache key
  """
  @callback store(cache, key, stored_value) :: true | {:error, error}

  @doc ~s"""
  Get the value for the given key from the cache. If there is no record with this
  key, execute `fun`, store its value under the `key` key if and only if it is not
  an error and return in. If there are more than one queries for that key, `fun`
  must be executed only once and the rest of the queries will wait until the result
  is ready.
  """
  @callback get_or_store(cache, key, fun, fun) :: {:ok, stored_value} | {:error, error}

  @callback size(cache, size_type) :: float()

  @callback clear_all(cache) :: :ok
end
