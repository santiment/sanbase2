defmodule Sanbase.ApiCallLimit.UsageAndLimitsTest do
  use Sanbase.DataCase, async: false

  @moduletag :api_call_counting

  import Sanbase.Factory

  alias Sanbase.ApiCallLimit

  setup do
    ApiCallLimit.ETS.clear_all()

    user = insert(:user, email: "usage_and_limits@gmail.com")

    %{user: user}
  end

  test "free plan user without any api calls", %{user: user} do
    assert {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)

    assert result.plan == "sanapi_free"
    assert result.has_limits == true
    assert result.api_calls_made == %{month: 0, hour: 0, minute: 0}
    assert result.api_calls_limits == %{month: 1000, hour: 500, minute: 100}
    assert result.api_calls_remaining == %{month: 1000, hour: 500, minute: 100}
  end

  test "the made and remaining calls reflect the recorded usage", %{user: user} do
    {:ok, _} = ApiCallLimit.get_quota_db(:user, user)
    {:ok, :updated} = ApiCallLimit.update_usage_db(:user, user, 10, 0)

    assert {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)

    assert result.api_calls_made == %{month: 10, hour: 10, minute: 10}
    assert result.api_calls_remaining == %{month: 990, hour: 490, minute: 90}
  end

  test "does not error when the limits are already exceeded", %{user: user} do
    {:ok, _} = ApiCallLimit.get_quota_db(:user, user)
    {:ok, :updated} = ApiCallLimit.update_usage_db(:user, user, 5000, 0)

    assert {:error, %{reason: :rate_limited}} = ApiCallLimit.get_quota_db(:user, user)

    assert {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)

    assert result.api_calls_made == %{month: 5000, hour: 5000, minute: 5000}
    assert result.api_calls_remaining == %{month: 0, hour: 0, minute: 0}
  end

  test "the counters are zeroed after a reset", %{user: user} do
    {:ok, _} = ApiCallLimit.get_quota_db(:user, user)
    {:ok, :updated} = ApiCallLimit.update_usage_db(:user, user, 10, 0)
    {:ok, _} = ApiCallLimit.reset(user)

    assert {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)

    assert result.api_calls_made == %{month: 0, hour: 0, minute: 0}
    assert result.api_calls_remaining == %{month: 1000, hour: 500, minute: 100}
  end

  test "no limits for a paid plan user" do
    user = insert(:user, email: "pro_user@gmail.com")
    insert(:subscription_pro, user: user)

    assert {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)

    assert result.plan == "sanapi_pro"
    assert result.has_limits == true
    assert result.api_calls_limits == %{month: 600_000, hour: 30_000, minute: 600}
  end

  test "users without limits have no limits and no remaining calls" do
    san_user = insert(:user, email: "dev@santiment.net")

    assert {:ok, result} = ApiCallLimit.usage_and_limits(:user, san_user)

    assert result.has_limits == false
    assert result.api_calls_made == %{month: 0, hour: 0, minute: 0}
    assert result.api_calls_limits == nil
    assert result.api_calls_remaining == nil
  end
end
