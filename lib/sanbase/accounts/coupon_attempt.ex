defmodule Sanbase.Accounts.CouponAttempt do
  alias Sanbase.Accounts.AccessAttempt

  def config do
    %{
      interval_in_minutes: 10,
      allowed_user_attempts: 5,
      allowed_ip_attempts: 20
    }
  end

  def check_attempt_limit(user, remote_ip) do
    AccessAttempt.check_attempt_limit("coupon", user, remote_ip)
  end

  def create(user, remote_ip) do
    AccessAttempt.create("coupon", user, remote_ip)
  end
end
