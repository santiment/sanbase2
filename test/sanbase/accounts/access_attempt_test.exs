defmodule Sanbase.Accounts.AccessAttemptTest do
  use Sanbase.DataCase, async: true
  alias Sanbase.Accounts.{AccessAttempt, EmailLoginAttempt}
  alias Sanbase.Repo
  import Sanbase.Factory

  setup do
    user = insert(:user)
    ip = "127.0.0.1"
    type = "email_login"
    config = EmailLoginAttempt.config()
    {:ok, user: user, ip: ip, type: type, config: config}
  end

  describe "check_attempt_limit/3" do
    test "allows attempts within user burst limits", %{
      user: user,
      ip: ip,
      type: type,
      config: config
    } do
      for _i <- 1..(config.allowed_user_burst_attempts + 1) do
        {:ok, _} = AccessAttempt.create(type, user, ip)
      end

      assert {:error, :too_many_burst_attempts} =
               AccessAttempt.check_attempt_limit(type, user, ip)
    end

    test "allows attempts within IP burst limits", %{ip: ip, type: type, config: config} do
      for _i <- 1..(config.allowed_ip_burst_attempts + 1) do
        user = insert(:user)
        {:ok, _} = AccessAttempt.create(type, user, ip)
      end

      new_user = insert(:user)

      assert {:error, :too_many_burst_attempts} =
               AccessAttempt.check_attempt_limit(type, new_user, ip)
    end

    test "allows attempts within user daily limits", %{
      user: user,
      ip: ip,
      type: type,
      config: config
    } do
      # Create attempts just under daily limit but over burst limit
      # Set them in the past to avoid burst limit interference
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for _i <- 1..(config.allowed_user_daily_attempts + 1) do
        {:ok, attempt} = AccessAttempt.create(type, user, ip)

        Repo.update_all(from(a in AccessAttempt, where: a.id == ^attempt.id),
          set: [inserted_at: past_time]
        )
      end

      assert {:error, :too_many_daily_attempts} =
               AccessAttempt.check_attempt_limit(type, user, ip)
    end

    test "allows attempts within IP daily limits", %{ip: ip, type: type, config: config} do
      # Create attempts just under daily limit but over burst limit
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for _i <- 1..(config.allowed_ip_daily_attempts + 1) do
        user = insert(:user)
        {:ok, attempt} = AccessAttempt.create(type, user, ip)

        Repo.update_all(from(a in AccessAttempt, where: a.id == ^attempt.id),
          set: [inserted_at: past_time]
        )
      end

      new_user = insert(:user)

      assert {:error, :too_many_daily_attempts} =
               AccessAttempt.check_attempt_limit(type, new_user, ip)
    end

    test "resets attempts count after burst interval", %{
      user: user,
      ip: ip,
      type: type,
      config: config
    } do
      # Make maximum allowed burst attempts
      for _i <- 1..(config.allowed_user_burst_attempts + 1) do
        {:ok, _} = AccessAttempt.create(type, user, ip)
      end

      assert {:error, :too_many_burst_attempts} =
               AccessAttempt.check_attempt_limit(type, user, ip)

      # Time travel past the burst interval
      past_time =
        DateTime.utc_now() |> DateTime.add(-(config.burst_interval_in_minutes + 1), :minute)

      Repo.update_all(
        from(a in AccessAttempt, where: a.user_id == ^user.id),
        set: [inserted_at: past_time]
      )

      # Should allow new attempts
      assert :ok = AccessAttempt.check_attempt_limit(type, user, ip)
    end

    test "resets attempts count after daily interval", %{
      user: user,
      ip: ip,
      type: type,
      config: config
    } do
      # Create attempts at daily limit
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for _i <- 1..(config.allowed_user_daily_attempts + 1) do
        {:ok, attempt} = AccessAttempt.create(type, user, ip)

        Repo.update_all(from(a in AccessAttempt, where: a.id == ^attempt.id),
          set: [inserted_at: past_time]
        )
      end

      assert {:error, :too_many_daily_attempts} =
               AccessAttempt.check_attempt_limit(type, user, ip)

      # Time travel past the daily interval
      very_past_time =
        DateTime.utc_now() |> DateTime.add(-(config.daily_interval_in_minutes + 1), :minute)

      Repo.update_all(
        from(a in AccessAttempt, where: a.user_id == ^user.id),
        set: [inserted_at: very_past_time]
      )

      # Should allow new attempts
      assert :ok = AccessAttempt.check_attempt_limit(type, user, ip)
    end
  end

  describe "check_ip_attempt_limit/2" do
    test "allows attempts within IP burst limits", %{ip: ip, type: type, config: config} do
      for _i <- 1..(config.allowed_ip_burst_attempts + 1) do
        user = insert(:user)
        {:ok, _} = AccessAttempt.create(type, user, ip)
      end

      assert {:error, :too_many_burst_attempts} = AccessAttempt.check_ip_attempt_limit(type, ip)
    end

    test "allows attempts within IP daily limits", %{ip: ip, type: type, config: config} do
      # Create attempts just under daily limit but over burst limit
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for _i <- 1..(config.allowed_ip_daily_attempts + 1) do
        user = insert(:user)
        {:ok, attempt} = AccessAttempt.create(type, user, ip)

        Repo.update_all(from(a in AccessAttempt, where: a.id == ^attempt.id),
          set: [inserted_at: past_time]
        )
      end

      assert {:error, :too_many_daily_attempts} = AccessAttempt.check_ip_attempt_limit(type, ip)
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
      for _i <- 1..(config.allowed_user_burst_attempts + 1) do
        {:ok, _} = AccessAttempt.create("email_login", user, ip)
      end

      assert {:error, :too_many_burst_attempts} =
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
    test "allows attempts within coupon-specific user burst limits", %{user: user, ip: ip} do
      config = Sanbase.Accounts.CouponAttempt.config()

      for _i <- 1..(config.allowed_user_burst_attempts + 1) do
        {:ok, _} = AccessAttempt.create("coupon", user, ip)
      end

      assert {:error, :too_many_burst_attempts} =
               AccessAttempt.check_attempt_limit("coupon", user, ip)
    end

    test "allows attempts within coupon-specific IP burst limits", %{ip: ip} do
      config = Sanbase.Accounts.CouponAttempt.config()

      for _i <- 1..(config.allowed_ip_burst_attempts + 1) do
        user = insert(:user)
        {:ok, _} = AccessAttempt.create("coupon", user, ip)
      end

      new_user = insert(:user)

      assert {:error, :too_many_burst_attempts} =
               AccessAttempt.check_attempt_limit("coupon", new_user, ip)
    end

    test "allows attempts within coupon-specific user daily limits", %{user: user, ip: ip} do
      config = Sanbase.Accounts.CouponAttempt.config()
      # Create attempts just under daily limit but over burst limit
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for _i <- 1..(config.allowed_user_daily_attempts + 1) do
        {:ok, attempt} = AccessAttempt.create("coupon", user, ip)

        Repo.update_all(from(a in AccessAttempt, where: a.id == ^attempt.id),
          set: [inserted_at: past_time]
        )
      end

      assert {:error, :too_many_daily_attempts} =
               AccessAttempt.check_attempt_limit("coupon", user, ip)
    end

    test "allows attempts within coupon-specific IP daily limits", %{ip: ip} do
      config = Sanbase.Accounts.CouponAttempt.config()
      # Create attempts just under daily limit but over burst limit
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for _i <- 1..(config.allowed_ip_daily_attempts + 1) do
        user = insert(:user)
        {:ok, attempt} = AccessAttempt.create("coupon", user, ip)

        Repo.update_all(from(a in AccessAttempt, where: a.id == ^attempt.id),
          set: [inserted_at: past_time]
        )
      end

      new_user = insert(:user)

      assert {:error, :too_many_daily_attempts} =
               AccessAttempt.check_attempt_limit("coupon", new_user, ip)
    end

    test "resets coupon attempts after burst interval", %{user: user, ip: ip} do
      config = Sanbase.Accounts.CouponAttempt.config()

      # Make maximum allowed burst attempts
      for _i <- 1..(config.allowed_user_burst_attempts + 1) do
        {:ok, _} = AccessAttempt.create("coupon", user, ip)
      end

      assert {:error, :too_many_burst_attempts} =
               AccessAttempt.check_attempt_limit("coupon", user, ip)

      # Time travel past the burst interval
      past_time =
        DateTime.utc_now() |> DateTime.add(-(config.burst_interval_in_minutes + 1), :minute)

      Repo.update_all(
        from(a in AccessAttempt, where: a.user_id == ^user.id),
        set: [inserted_at: past_time]
      )

      # Should allow new attempts
      assert :ok = AccessAttempt.check_attempt_limit("coupon", user, ip)
    end

    test "resets coupon attempts after daily interval", %{user: user, ip: ip} do
      config = Sanbase.Accounts.CouponAttempt.config()
      # Create attempts at daily limit
      past_time = DateTime.utc_now() |> DateTime.add(-10, :minute)

      for _i <- 1..(config.allowed_user_daily_attempts + 1) do
        {:ok, attempt} = AccessAttempt.create("coupon", user, ip)

        Repo.update_all(from(a in AccessAttempt, where: a.id == ^attempt.id),
          set: [inserted_at: past_time]
        )
      end

      assert {:error, :too_many_daily_attempts} =
               AccessAttempt.check_attempt_limit("coupon", user, ip)

      # Time travel past the daily interval
      very_past_time =
        DateTime.utc_now() |> DateTime.add(-(config.daily_interval_in_minutes + 1), :minute)

      Repo.update_all(
        from(a in AccessAttempt, where: a.user_id == ^user.id),
        set: [inserted_at: very_past_time]
      )

      # Should allow new attempts
      assert :ok = AccessAttempt.check_attempt_limit("coupon", user, ip)
    end
  end
end
