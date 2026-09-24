defmodule Sanbase.Accounts.CouponAttempt do
  @behaviour Sanbase.Accounts.AccessAttemptBehaviour
  alias Sanbase.Accounts.AccessAttempt

  @impl true
  def type, do: "coupon"

  # high limits due to frontend checking for coupon on keypress
  @impl true
  def config do
    %{
      # Burst limits (short-term protection)
      burst_interval_in_minutes: 5,
      allowed_user_burst_attempts: 30,
      allowed_ip_burst_attempts: 60,

      # Daily limits (long-term protection)
      # 24 hours
      daily_interval_in_minutes: 24 * 60,
      allowed_user_daily_attempts: 200,
      allowed_ip_daily_attempts: 500
    }
  end

  @impl true
  def check_attempt_limit(user, remote_ip) do
    AccessAttempt.check_attempt_limit(type(), user, remote_ip)
  end

  def check_ip_attempt_limit(remote_ip) do
    AccessAttempt.check_ip_attempt_limit(type(), remote_ip)
  end

  @impl true
  def create(user, remote_ip) do
    AccessAttempt.create(type(), user, remote_ip)
  end
end
