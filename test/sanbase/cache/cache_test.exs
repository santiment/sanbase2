defmodule Sanbase.CacheTest do
  use ExUnit.Case, async: true

  alias Sanbase.Cache
  alias Sanbase.RequestContext

  describe "hash/1 — :context strip" do
    test "stripping a top-level :context keyword pair does not change the hash" do
      base = [slug: "bitcoin", from: ~U[2024-01-01 00:00:00Z]]
      with_ctx = Keyword.put(base, :context, RequestContext.anonymous(:graphql))

      assert Cache.hash(base) == Cache.hash(with_ctx)
    end

    test "two different RequestContexts hash the same when threaded as :context" do
      protected_ctx = %RequestContext{origin: :graphql, user_id: 1, privacy_protected: true}

      non_protected_ctx = %RequestContext{
        origin: :graphql,
        user_id: 9_999,
        privacy_protected: false
      }

      args_a = [slug: "ethereum", context: protected_ctx]
      args_b = [slug: "ethereum", context: non_protected_ctx]

      assert Cache.hash(args_a) == Cache.hash(args_b)
    end

    test "%RequestContext{} nested deeper than top level is also collapsed" do
      ctx = RequestContext.anonymous(:graphql)
      a = {:get_metric, "price_usd", [from: ~U[2024-01-01 00:00:00Z], context: ctx]}
      b = {:get_metric, "price_usd", [from: ~U[2024-01-01 00:00:00Z]]}

      assert Cache.hash(a) == Cache.hash(b)
    end

    test "non-context fields still differentiate cache keys" do
      ctx = RequestContext.anonymous(:graphql)
      a = [slug: "bitcoin", context: ctx]
      b = [slug: "ethereum", context: ctx]

      refute Cache.hash(a) == Cache.hash(b)
    end

    test "DateTime / Date structs are preserved (cache keys for them are stable)" do
      # Regression guard: the strip must not flatten foreign structs to
      # plain maps, otherwise every existing cache key changes on deploy.
      a = [from: ~U[2024-01-01 00:00:00Z]]
      b = [from: ~U[2024-01-01 00:00:00Z]]
      c = [from: ~U[2024-01-02 00:00:00Z]]

      assert Cache.hash(a) == Cache.hash(b)
      refute Cache.hash(a) == Cache.hash(c)
    end

    test ":context inside a plain map is stripped" do
      ctx = RequestContext.anonymous(:graphql)
      a = %{slug: "bitcoin", context: ctx}
      b = %{slug: "bitcoin"}

      assert Cache.hash(a) == Cache.hash(b)
    end
  end
end
