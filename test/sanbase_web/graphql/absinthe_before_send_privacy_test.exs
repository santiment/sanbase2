defmodule SanbaseWeb.Graphql.AbsintheBeforeSendPrivacyTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts
  alias SanbaseWeb.Graphql.AbsintheBeforeSend

  setup do
    protected = insert(:user)
    unprotected = insert(:user)
    Sanbase.PrivacyCacheSeed.seed!([protected.id])
    {:ok, protected: protected, unprotected: unprotected}
  end

  defp metadata(user_id, queries) do
    %{
      request_id: "req-1",
      timestamp: 1_700_000_000,
      has_graphql_errors: false,
      duration_ms: 12,
      user_agent: "test/1.0",
      queries: queries,
      success_queries: queries,
      success_queries_count: length(queries),
      error_queries: [],
      result_sizes: %{byte_size: 100, compressed_byte_size: 60, min_byte_size: 60},
      caller_data: %{
        user_id: user_id,
        san_balance: nil,
        auth_method: :apikey,
        api_token: "tok"
      },
      remote_ip: "127.0.0.1",
      partial_context: %{}
    }
  end

  describe "build_export_records/1" do
    test "masks query/selector/version for protected users; keeps user_id", %{protected: user} do
      masked = Accounts.masked_sentinel()

      meta =
        metadata(user.id, [
          {:get_metric, "myAlias", "price_usd", %{slug: "bitcoin"}, "v1"},
          "allProjects"
        ])

      [r1, r2] = AbsintheBeforeSend.build_export_records(meta)

      assert r1.query == masked
      assert r1.selector == Jason.encode!(nil)
      assert r1.version == nil
      assert r1.user_id == user.id

      assert r2.query == masked
      assert r2.selector == Jason.encode!(nil)
      assert r2.version == nil
    end

    test "non-protected user: getMetric expands to getMetric|<metric> with selector", %{
      unprotected: user
    } do
      meta =
        metadata(user.id, [
          {:get_metric, "alias", "price_usd", %{slug: "bitcoin"}, "v2"}
        ])

      [r] = AbsintheBeforeSend.build_export_records(meta)
      assert r.query == "getMetric|price_usd"
      assert r.selector == Jason.encode!(%{slug: "bitcoin"})
      assert r.version == "v2"
    end

    test "non-protected user: plain query string passes through", %{unprotected: user} do
      meta = metadata(user.id, ["allProjects"])
      [r] = AbsintheBeforeSend.build_export_records(meta)
      assert r.query == "allProjects"
      assert r.selector == Jason.encode!(nil)
      assert r.version == nil
    end

    test "anonymous (nil user_id): plain query passes through" do
      meta = metadata(nil, ["allProjects"])
      [r] = AbsintheBeforeSend.build_export_records(meta)
      assert r.query == "allProjects"
      assert r.user_id == nil
    end
  end
end
