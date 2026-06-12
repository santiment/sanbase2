defmodule Sanbase.PrivacyCacheSeed do
  @moduledoc """
  Test helper for `Sanbase.Accounts.ProtectedUser`'s `:persistent_term`
  cache. Tests that need a protected user id without touching the DB
  call `seed!/1` from `setup` to mark those ids as protected.

  The `:persistent_term` key is process-global and shared by every test.
  `seed!/1` therefore *adds* its ids to the existing set (union) rather
  than replacing it, so async tests running concurrently can't clobber
  each other's protected ids — each test seeds its own factory-created
  (hence unique) ids and only ever observes membership for those. The
  set is never shrunk, so no teardown is needed; it resets when the BEAM
  restarts.

  The DB-backed `Sanbase.Accounts.ProtectedUserTest` (async: false)
  needs exact control of the set, so it saves and restores the entry
  inside its own setup block instead of relying on this helper.
  """

  alias Sanbase.Accounts.ProtectedUser

  @spec seed!(Enumerable.t()) :: :ok
  def seed!(ids) do
    existing =
      case :persistent_term.get(ProtectedUser.cache_key(), nil) do
        {%MapSet{} = set, _added_at} -> set
        _ -> MapSet.new()
      end

    merged = MapSet.union(existing, MapSet.new(ids))

    :persistent_term.put(
      ProtectedUser.cache_key(),
      {merged, System.monotonic_time(:second)}
    )

    :ok
  end
end
