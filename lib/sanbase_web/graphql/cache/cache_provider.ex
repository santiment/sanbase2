defmodule SanbaseWeb.Graphql.CacheProvider do
  @moduledoc """
  Behaviour that the cache needs to conform to.
  """

  @type hash :: String.t()
  @type key :: hash | {atom, hash} | {non_neg_integer(), non_neg_integer()}
  @type error :: String.t()
  @type stored_value :: any()
  @type cache :: atom()
  @type size_type :: :megabytes

  @callback start_link(Keyword.t()) :: {:ok, pid}

  @callback child_spec(Keyword.t()) :: Supervisor.child_spec()

  @doc ~s"""
  Get the value for the given key from the cache
  """
  @callback get(cache, hash) :: {:ok, any} | {:error, error} | nil

  @doc ~s"""
  Put a query document in the cache with the key as cache key
  """
  @callback store(cache, key, stored_value) :: :ok | {:error, error}

  @doc ~s"""
  Get the value for the given key from the cache. If there is no record with this
  key, execute `fun`, store its value under the `key` key if and only if it is not
  an error and return in. If there are more than one queries for that key, `fun`
  must be executed only once and the rest of the queries will wait until the result
  is ready.
  """
  @callback get_or_store(cache, key, fun, fun) :: {:ok, stored_value} | {:error, error}

  @doc ~s"""
  Get the size of the cache in megabytes
  """
  @callback size(cache) :: float()

  @doc ~s"""
  Count the elements in the cache
  """
  @callback count(cache) :: non_neg_integer()

  @doc ~s"""
  Delete all objects in the cache. The cache itself is not deleted
  """
  @callback clear_all(cache) :: :ok
end
