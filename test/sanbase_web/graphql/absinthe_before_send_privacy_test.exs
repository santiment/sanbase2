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

  defp metadata(user_id, queries, hide_activity?) do
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
      partial_context: %{},
      hide_activity?: hide_activity?
    }
  end

  describe "build_export_records/1" do
    test "masks query/selector/version + api_token/remote_ip/user_agent for protected users; keeps user_id",
         %{protected: user} do
      masked = Accounts.masked_sentinel()

      meta =
        metadata(
          user.id,
          [
            {:get_metric, "myAlias", "price_usd", %{slug: "bitcoin"}, "v1"},
            "allProjects"
          ],
          true
        )

      [r1, r2] = AbsintheBeforeSend.build_export_records(meta)

      for r <- [r1, r2] do
        assert r.query == masked
        assert r.selector == Jason.encode!(nil)
        assert r.version == nil
        # user_id kept for billing reconciliation
        assert r.user_id == user.id
        # NDA-sensitive identifiers must not leak
        assert r.api_token == nil
        assert r.remote_ip == nil
        assert r.user_agent == nil
      end
    end

    test "non-protected user: getMetric expands to getMetric|<metric>, identifiers preserved",
         %{unprotected: user} do
      meta =
        metadata(
          user.id,
          [{:get_metric, "alias", "price_usd", %{slug: "bitcoin"}, "v2"}],
          false
        )

      [r] = AbsintheBeforeSend.build_export_records(meta)
      assert r.query == "getMetric|price_usd"
      assert r.selector == Jason.encode!(%{slug: "bitcoin"})
      assert r.version == "v2"
      assert r.api_token == "tok"
      assert r.remote_ip == "127.0.0.1"
      assert r.user_agent == "test/1.0"
    end

    test "non-protected user: plain query string passes through", %{unprotected: user} do
      meta = metadata(user.id, ["allProjects"], false)
      [r] = AbsintheBeforeSend.build_export_records(meta)
      assert r.query == "allProjects"
      assert r.selector == Jason.encode!(nil)
      assert r.version == nil
    end

    test "anonymous (nil user_id): plain query passes through" do
      meta = metadata(nil, ["allProjects"], false)
      [r] = AbsintheBeforeSend.build_export_records(meta)
      assert r.query == "allProjects"
      assert r.user_id == nil
    end
  end
end
