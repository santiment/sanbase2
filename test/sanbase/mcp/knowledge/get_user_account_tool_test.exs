defmodule Sanbase.MCP.Knowledge.GetUserAccountToolTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.InvoiceMirror
  alias Sanbase.MCP.Knowledge.GetUserAccountTool
  alias Sanbase.Repo

  @moduletag capture_log: true

  setup do
    ApiCallLimit.ETS.clear_all()

    support = insert(:user, email: "support@santiment.net")
    customer = insert(:user, email: "Customer@Example.com", username: "customer")

    %{customer: customer, frame: Frame.new(%{current_user: support})}
  end

  defp call(params, frame) do
    {:reply, %Response{} = response, _frame} = GetUserAccountTool.execute(params, frame)
    protocol = Response.to_protocol(response)
    [%{"text" => text}] = protocol["content"]

    if protocol["isError"], do: {:error, text}, else: {:ok, Jason.decode!(text)}
  end

  # Stores `count` calls in each window `now` falls in. `update_usage_db/4` keys them by
  # its own clock, so a read at another instant could cross a minute or hour boundary.
  defp put_usage(user, now, count) do
    {:ok, _} = ApiCallLimit.get_quota_db(:user, user)

    api_calls =
      now |> ApiCallLimit.period_starts() |> Map.new(fn {_, dt} -> {to_string(dt), count} end)

    Repo.get_by!(ApiCallLimit, user_id: user.id)
    |> ApiCallLimit.changeset(%{api_calls: api_calls})
    |> Repo.update!()
  end

  test "finds the user by id, email in any casing or username", %{
    customer: customer,
    frame: frame
  } do
    for term <- [customer.id, to_string(customer.id), "customer@example.com", "customer"] do
      assert {:ok, %{"user" => %{"id" => id}}} = call(%{user: term}, frame)
      assert id == customer.id
    end

    assert {:error, "[permanent] No user found" <> _} = call(%{user: "nobody@x.com"}, frame)
    assert {:error, "[permanent] Pass a user id" <> _} = call(%{user: " "}, frame)
  end

  test "falls back to the username when no id or email matches", %{frame: frame} do
    numeric = insert(:user, username: "4242424242")
    with_at = insert(:user, username: "joe@home")

    assert {:ok, %{"user" => %{"id" => id}}} = call(%{user: "4242424242"}, frame)
    assert id == numeric.id

    assert {:ok, %{"user" => %{"id" => id}}} = call(%{user: "joe@home"}, frame)
    assert id == with_at.id

    # Beyond bigint: not found, rather than a Postgrex encoding error.
    assert {:error, "[permanent] No user found" <> _} =
             call(%{user: "99999999999999999999"}, frame)
  end

  test "returns the account and subscriptions without creating limit rows", %{
    customer: customer,
    frame: frame
  } do
    insert(:subscription_pro, user: customer)

    assert {:ok, result} = call(%{user: customer.id}, frame)

    assert result["user"]["email"] == "Customer@Example.com"
    assert result["user"]["mcp_ban"] == nil

    assert [%{"status" => "active", "plan" => "PRO", "updated_at" => _}] =
             result["subscriptions"]

    assert {:ok, _, 0} = DateTime.from_iso8601(result["as_of"])
    assert result["api_limits"]["as_of"] == result["as_of"]
    assert result["api_limits"]["message"] =~ "never made an authenticated call"
    refute Map.has_key?(result, "api_usage")

    assert result["admin_links"]["overview"] =~ "user_id=#{customer.id}"

    assert Repo.get_by(ApiCallLimit, user_id: customer.id) == nil
  end

  test "returns the API calls made from the limits record", %{customer: customer, frame: frame} do
    put_usage(customer, DateTime.utc_now(), 12)

    assert {:ok, %{"api_limits" => limits} = result} = call(%{user: customer.id}, frame)

    assert limits["as_of"] == result["as_of"]
    assert limits["plan"] == "sanapi_free"
    assert limits["api_calls_limits"] == %{"month" => 1000, "hour" => 500, "minute" => 100}
    assert limits["api_calls_made"]["month"] == 12
    assert limits["api_calls_remaining"]["month"] == 988
    assert limits["blocked"] == nil
  end

  test "gives each current subscription the limits of its plan", %{
    customer: customer,
    frame: frame
  } do
    sanbase = insert(:subscription_pro_sanbase, user: customer)
    api = insert(:subscription_pro, user: customer)
    canceled = insert(:subscription_essential, user: customer, status: "canceled")

    assert {:ok, %{"subscriptions" => subscriptions}} = call(%{user: customer.id}, frame)
    by_id = Map.new(subscriptions, &{&1["id"], &1})

    assert %{"api_call_limits" => %{"month" => 600_000, "hour" => 30_000, "minute" => 600}} =
             by_id[api.id]

    assert %{"api_call_limits" => %{"month" => 5000, "hour" => 1000, "minute" => 100}} =
             by_id[sanbase.id]

    refute Map.has_key?(by_id[canceled.id], "api_call_limits")
  end

  test "a plan without limits is reported as unlimited", %{customer: customer, frame: frame} do
    custom = insert(:subscription_custom, user: customer)

    assert {:ok, %{"subscriptions" => [subscription]}} = call(%{user: customer.id}, frame)
    assert %{"id" => id, "api_call_limits" => "unlimited"} = subscription
    assert id == custom.id
  end

  test "reports a rate-limited user as blocked", %{customer: customer, frame: frame} do
    put_usage(customer, DateTime.utc_now(), 5000)

    assert {:ok, %{"api_limits" => limits}} = call(%{user: customer.id}, frame)

    assert limits["api_calls_remaining"]["month"] == 0
    assert %{"reason" => "rate_limited", "blocked_until" => until} = limits["blocked"]
    assert until > limits["as_of"]
  end

  test "ApiCallLimit.status/3 counts the windows `now` falls in", %{customer: customer} do
    now = DateTime.utc_now()
    put_usage(customer, now, 10)

    assert {:ok, status} = ApiCallLimit.status(:user, customer, now)
    assert status.as_of == now
    assert status.period_starts == ApiCallLimit.period_starts(now)
    assert status.api_calls_made == %{month: 10, hour: 10, minute: 10}
    assert status.blocked == nil

    # Two hours on, the calls are outside the hour and minute windows.
    later = DateTime.add(now, 2, :hour)

    assert {:ok, %{as_of: ^later, api_calls_made: %{hour: 0, minute: 0}}} =
             ApiCallLimit.status(:user, customer, later)
  end

  test "a monthly block lasts until the next month starts", %{customer: customer} do
    next_month = ~U[2026-11-01 00:00:00Z]

    now = ~U[2026-10-15 12:00:00Z]
    put_usage(customer, now, 1000)
    assert {:ok, %{blocked: blocked}} = ApiCallLimit.status(:user, customer, now)
    assert %{reason: :rate_limited, blocked_until: ^next_month} = blocked
    assert blocked.blocked_for_seconds == DateTime.diff(next_month, now)

    # Half a second before the reset: still blocked for a (rounded up) second.
    now = ~U[2026-10-31 23:59:59.500000Z]
    put_usage(customer, now, 1000)
    assert {:ok, %{blocked: blocked}} = ApiCallLimit.status(:user, customer, now)
    assert blocked.blocked_for_seconds == 1
    assert DateTime.compare(blocked.blocked_until, next_month) == :gt
  end

  test "a failing section leaves the rest", %{customer: customer, frame: frame} do
    Sanbase.Mock.prepare_mock(InvoiceMirror, :last_synced_at, fn -> raise "mirror down" end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, result} = call(%{user: customer.id}, frame)

      assert result["invoices"]["error"] =~ "mirror down"
      assert result["user"]["id"] == customer.id
      assert is_list(result["subscriptions"])
      assert is_map(result["api_limits"])
    end)
  end
end
