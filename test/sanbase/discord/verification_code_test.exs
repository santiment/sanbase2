defmodule Sanbase.Discord.VerificationCodeTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  alias Sanbase.Discord.VerificationCode

  describe "generate_code/2" do
    test "generates a unique code for a user and tier" do
      user = insert(:user)
      tier = "PRO"

      {:ok, verification_code} = VerificationCode.generate_code(user.id, tier)

      assert verification_code.user_id == user.id
      assert verification_code.subscription_tier == tier
      assert verification_code.code =~ ~r/^PRO-/
      # PRO- + 6 chars
      assert String.length(verification_code.code) == 10
      assert verification_code.used == false
      assert verification_code.verified_at == nil
      assert verification_code.discord_user_id == nil
      assert verification_code.discord_username == nil
    end

    test "generates different codes for different users" do
      user1 = insert(:user)
      user2 = insert(:user)
      tier = "PRO"

      {:ok, code1} = VerificationCode.generate_code(user1.id, tier)
      {:ok, code2} = VerificationCode.generate_code(user2.id, tier)

      refute code1.code == code2.code
    end

    test "generates codes with PRO prefix regardless of tier" do
      user = insert(:user)

      # Test all tiers generate PRO- prefix
      for tier <- ["PRO", "MAX", "BUSINESS_PRO", "BUSINESS_MAX"] do
        {:ok, verification_code} = VerificationCode.generate_code(user.id, tier)
        assert String.starts_with?(verification_code.code, "PRO-")
        # PRO-XXXXXX
        assert String.length(verification_code.code) == 10
      end
    end

    test "cleans up existing codes for user before generating new one" do
      user = insert(:user)
      tier = "PRO"

      # Generate first code
      {:ok, _code1} = VerificationCode.generate_code(user.id, tier)

      # Generate second code - should clean up first
      {:ok, code2} = VerificationCode.generate_code(user.id, tier)

      # Should only have one active code
      active_codes =
        from(vc in VerificationCode, where: vc.user_id == ^user.id)
        |> Sanbase.Repo.all()

      assert length(active_codes) == 1
      assert hd(active_codes).id == code2.id
    end
  end

  describe "verify_code/2" do
    test "successfully verifies a valid code" do
      user = insert(:user)
      tier = "PRO"
      discord_user_id = "123456789"

      {:ok, verification_code} = VerificationCode.generate_code(user.id, tier)

      {:ok, updated_code} = VerificationCode.verify_code(verification_code.code, discord_user_id)

      assert updated_code.used == true
      assert updated_code.verified_at != nil
      assert updated_code.discord_user_id == discord_user_id
      assert updated_code.discord_username != nil
    end

    test "returns error for invalid code" do
      discord_user_id = "123456789"

      {:error, :invalid_code} = VerificationCode.verify_code("INVALID-CODE", discord_user_id)
    end

    test "returns error for already used code" do
      user = insert(:user)
      tier = "PRO"
      discord_user_id = "123456789"

      {:ok, verification_code} = VerificationCode.generate_code(user.id, tier)

      # Verify once
      {:ok, _} = VerificationCode.verify_code(verification_code.code, discord_user_id)

      # Try to verify again
      {:error, :already_used} = VerificationCode.verify_code(verification_code.code, "987654321")
    end

    test "returns error for expired code" do
      user = insert(:user)
      tier = "PRO"
      discord_user_id = "123456789"

      # Create an expired code
      expired_code =
        %VerificationCode{
          code: "PRO-EXPIRED-#{user.id}",
          user_id: user.id,
          subscription_tier: tier,
          # 1 second ago
          expires_at: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second),
          used: false
        }
        |> Sanbase.Repo.insert!()

      {:error, :expired} = VerificationCode.verify_code(expired_code.code, discord_user_id)
    end
  end

  describe "get_active_code_for_user/1" do
    test "returns active code for user" do
      user = insert(:user)
      tier = "PRO"

      {:ok, verification_code} = VerificationCode.generate_code(user.id, tier)

      active_code = VerificationCode.get_active_code_for_user(user.id)

      assert active_code.id == verification_code.id
    end

    test "returns nil when no active code exists" do
      user = insert(:user)

      assert VerificationCode.get_active_code_for_user(user.id) == nil
    end

    test "returns nil for expired code" do
      user = insert(:user)
      tier = "PRO"

      # Create an expired code
      %VerificationCode{
        code: "PRO-EXPIRED-#{user.id}",
        user_id: user.id,
        subscription_tier: tier,
        # 1 second ago
        expires_at: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second),
        used: false
      }
      |> Sanbase.Repo.insert!()

      assert VerificationCode.get_active_code_for_user(user.id) == nil
    end
  end

  describe "cleanup_expired/0" do
    test "removes expired codes" do
      user1 = insert(:user)
      user2 = insert(:user)
      tier = "PRO"

      # Create expired code for user1
      %VerificationCode{
        code: "PRO-EXPIRED-#{user1.id}",
        user_id: user1.id,
        subscription_tier: tier,
        # 1 second ago
        expires_at: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second),
        used: false
      }
      |> Sanbase.Repo.insert!()

      # Create valid code for user2
      {:ok, _valid_code} = VerificationCode.generate_code(user2.id, tier)

      # Cleanup expired codes
      {count, _} = VerificationCode.cleanup_expired()

      assert count >= 1

      # Should only have the valid code left
      active_codes =
        from(vc in VerificationCode, where: vc.user_id == ^user2.id)
        |> Sanbase.Repo.all()

      assert length(active_codes) == 1
    end
  end
end
