defmodule Sanbase.Accounts.AccessAttemptTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.AccessAttempt
  alias Sanbase.Accounts.CouponAttempt
  alias Sanbase.Accounts.EmailLoginAttempt
  alias Sanbase.Repo

  setup do
    user = insert(:user)
    ip = "127.0.0.1"
    type = "email_login"
    config = EmailLoginAttempt.config()
    {:ok, user: user, ip: ip, type: type, config: config}
  end

  describe "check_attempt_limit/3" do
    test "allows attempts within user limits", %{user: user, ip: ip, type: type, config: config} do
      for _i <- 1..(config.allowed_user_attempts + 1) do
        {:ok, _} = AccessAttempt.create(type, user, ip)
      end

      assert {:error, :too_many_attempts} = AccessAttempt.check_attempt_limit(type, user, ip)
    end

    test "allows attempts within IP limits", %{ip: ip, type: type, config: config} do
      for _i <- 1..(config.allowed_ip_attempts + 1) do
        user = insert(:user)
        {:ok, _} = AccessAttempt.create(type, user, ip)
      end

      new_user = insert(:user)

      assert {:error, :too_many_attempts} =
               AccessAttempt.check_attempt_limit(type, new_user, ip)
    end

    test "resets attempts count after interval", %{user: user, ip: ip, type: type, config: config} do
      # Make maximum allowed attempts
      for _i <- 1..(config.allowed_user_attempts + 1) do
        {:ok, _} = AccessAttempt.create(type, user, ip)
      end

      assert {:error, :too_many_attempts} = AccessAttempt.check_attempt_limit(type, user, ip)

      # Time travel past the interval by updating timestamps
      past_time = DateTime.add(DateTime.utc_now(), -(config.interval_in_minutes + 1), :minute)

      Repo.update_all(
        from(a in AccessAttempt, where: a.user_id == ^user.id),
        set: [inserted_at: past_time]
      )

      # Should allow new attempts
      assert :ok = AccessAttempt.check_attempt_limit(type, user, ip)
    end
  end

  describe "create/3" do
    test "creates new attempt record", %{user: user, ip: ip, type: type} do
      assert {:ok, attempt} = AccessAttempt.create(type, user, ip)
      assert attempt.user_id == user.id
      assert attempt.ip_address == ip
      assert attempt.type == type
    end

    test "validates required fields" do
      assert {:error, changeset} = AccessAttempt.create(nil, nil, nil)
      assert "can't be blank" in errors_on(changeset).ip_address
      assert "can't be blank" in errors_on(changeset).type
    end
  end

  describe "different attempt types" do
    test "handles different rate limit configs", %{user: user, ip: ip, config: config} do
      for _i <- 1..(config.allowed_user_attempts + 1) do
        {:ok, _} = AccessAttempt.create("email_login", user, ip)
      end

      assert {:error, :too_many_attempts} =
               AccessAttempt.check_attempt_limit("email_login", user, ip)

      # Coupon attempts should still work (different type)
      assert :ok = AccessAttempt.check_attempt_limit("coupon", user, ip)
    end

    test "raises for unknown attempt type", %{user: user, ip: ip} do
      assert_raise RuntimeError, "Unknown access attempt type: unknown", fn ->
        AccessAttempt.check_attempt_limit("unknown", user, ip)
      end
    end
  end

  describe "coupon attempts" do
    test "allows attempts within coupon-specific user limits", %{user: user, ip: ip} do
      config = CouponAttempt.config()

      for _i <- 1..(config.allowed_user_attempts + 1) do
        {:ok, _} = AccessAttempt.create("coupon", user, ip)
      end

      assert {:error, :too_many_attempts} =
               AccessAttempt.check_attempt_limit("coupon", user, ip)
    end

    test "allows attempts within coupon-specific IP limits", %{ip: ip} do
      config = CouponAttempt.config()

      for _i <- 1..(config.allowed_ip_attempts + 1) do
        user = insert(:user)
        {:ok, _} = AccessAttempt.create("coupon", user, ip)
      end

      new_user = insert(:user)

      assert {:error, :too_many_attempts} =
               AccessAttempt.check_attempt_limit("coupon", new_user, ip)
    end

    test "resets coupon attempts after interval", %{user: user, ip: ip} do
      config = CouponAttempt.config()

      # Make maximum allowed attempts
      for _i <- 1..(config.allowed_user_attempts + 1) do
        {:ok, _} = AccessAttempt.create("coupon", user, ip)
      end

      assert {:error, :too_many_attempts} =
               AccessAttempt.check_attempt_limit("coupon", user, ip)

      # Time travel past the interval
      past_time = DateTime.add(DateTime.utc_now(), -(config.interval_in_minutes + 1), :minute)

      Repo.update_all(
        from(a in AccessAttempt, where: a.user_id == ^user.id),
        set: [inserted_at: past_time]
      )

      # Should allow new attempts
      assert :ok = AccessAttempt.check_attempt_limit("coupon", user, ip)
    end
  end
end
