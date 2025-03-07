defmodule Sanbase.Accounts.CouponAttempt do
  @behaviour Sanbase.Accounts.AccessAttemptBehaviour
  alias Sanbase.Accounts.AccessAttempt

  @impl true
  def type, do: "coupon"

  # high limits due to frontend checking for coupon on keypress
  @impl true
  def config do
    %{
      interval_in_minutes: 10,
      allowed_user_attempts: 30,
      allowed_ip_attempts: 60
    }
  end

  @impl true
  def check_attempt_limit(user, remote_ip) do
    AccessAttempt.check_attempt_limit(type(), user, remote_ip)
  end

  @impl true
  def create(user, remote_ip) do
    AccessAttempt.create(type(), user, remote_ip)
  end
end
