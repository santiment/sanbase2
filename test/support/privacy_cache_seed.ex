defmodule Sanbase.PrivacyCacheSeed do
  @moduledoc """
  Test helper for `Sanbase.Accounts.ProtectedUser`'s `:persistent_term`
  cache. Tests that need a protected user id without touching the DB
  call `seed!/1` from `setup` to inject a controlled MapSet.

  Idempotent and teardown-free on purpose: the key is process-global, so
  every async caller writes the same value and the cache stays warm
  between tests. The DB-backed `Sanbase.Accounts.ProtectedUserTest`
  (async: false) saves and restores the entry inside its own setup
  block, so it never collides with concurrent readers.
  """

  alias Sanbase.Accounts.ProtectedUser

  @spec seed!(Enumerable.t()) :: :ok
  def seed!(ids) do
    :persistent_term.put(
      ProtectedUser.cache_key(),
      {MapSet.new(ids), System.monotonic_time(:second)}
    )

    :ok
  end
end
