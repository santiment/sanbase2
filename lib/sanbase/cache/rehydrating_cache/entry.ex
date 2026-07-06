defmodule Sanbase.Cache.RehydratingCache.Entry do
  @moduledoc ~s"""
  Everything `Sanbase.Cache.RehydratingCache` tracks about a single registered
  key. Previously this lived in several parallel maps keyed by the same key
  (`functions`, `progress`, `backoffs`, `last_access`) that all had to be kept
  in sync; bundling them into one typed struct keeps a key's state in one place.

    * `function` - the 0-arity function that computes the value.
    * `key` - the key the value is stored under.
    * `ttl` - how long a computed value stays in the store (seconds).
    * `refresh_time_delta` - how often the value is recomputed (seconds).
    * `description` - optional human-readable label for the registration.
    * `progress` - the current computation lifecycle state (see `Progress`).
    * `last_access_unix` - unix seconds of the most recent read; drives
      pausing/dropping of keys that are no longer requested.
    * `backoff_count` - consecutive non-`{:ok, _}` completions, used for
      exponential retry backoff. Reset to 0 on a clean `{:ok, _}`.
  """

  alias Sanbase.Cache.RehydratingCache.Progress

  @enforce_keys [:function, :key, :ttl, :refresh_time_delta, :progress, :last_access_unix]
  defstruct [
    :function,
    :key,
    :ttl,
    :refresh_time_delta,
    :description,
    :progress,
    :last_access_unix,
    backoff_count: 0
  ]

  @type t :: %__MODULE__{
          function: (-> any()),
          key: any(),
          ttl: pos_integer(),
          refresh_time_delta: pos_integer(),
          description: String.t() | nil,
          progress: Progress.t(),
          last_access_unix: non_neg_integer(),
          backoff_count: non_neg_integer()
        }
end
