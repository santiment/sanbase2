defmodule SanbaseWeb.Graphql.AbsintheBeforeSendPrivacyTest do
  use ExUnit.Case, async: true

  alias Sanbase.Accounts
  alias SanbaseWeb.Graphql.AbsintheBeforeSend

  defp protected_id, do: Accounts.privacy_protected_user_ids() |> Enum.at(0)

  defp unprotected_id do
    Enum.find(10_000..20_000, fn id ->
      not MapSet.member?(Accounts.privacy_protected_user_ids(), id)
    end)
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
    test "masks query/selector/version for protected users; keeps user_id" do
      masked = Accounts.masked_sentinel()

      meta =
        metadata(protected_id(), [
          {:get_metric, "myAlias", "price_usd", %{slug: "bitcoin"}, "v1"},
          "allProjects"
        ])

      [r1, r2] = AbsintheBeforeSend.build_export_records(meta)

      assert r1.query == masked
      assert r1.selector == Jason.encode!(nil)
      assert r1.version == nil
      assert r1.user_id == protected_id()

      assert r2.query == masked
      assert r2.selector == Jason.encode!(nil)
      assert r2.version == nil
    end

    test "non-protected user: getMetric expands to getMetric|<metric> with selector" do
      meta =
        metadata(unprotected_id(), [
          {:get_metric, "alias", "price_usd", %{slug: "bitcoin"}, "v2"}
        ])

      [r] = AbsintheBeforeSend.build_export_records(meta)
      assert r.query == "getMetric|price_usd"
      assert r.selector == Jason.encode!(%{slug: "bitcoin"})
      assert r.version == "v2"
    end

    test "non-protected user: plain query string passes through" do
      meta = metadata(unprotected_id(), ["allProjects"])
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
