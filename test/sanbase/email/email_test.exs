defmodule Sanbase.EmailTest do
  use Sanbase.DataCase

  alias Sanbase.Email

  describe "email_excluded?/1" do
    test "returns true for excluded email" do
      Email.exclude_email("excluded@example.com", "Test exclusion")
      assert Email.email_excluded?("excluded@example.com")
    end

    test "returns false for non-excluded email" do
      refute Email.email_excluded?("allowed@example.com")
    end

    test "returns false for invalid input" do
      refute Email.email_excluded?(nil)
      refute Email.email_excluded?(123)
    end
  end

  describe "exclude_email/2" do
    test "excludes email with reason" do
      assert {:ok, exclusion} = Email.exclude_email("test@example.com", "User requested")
      assert exclusion.email == "test@example.com"
      assert exclusion.reason == "User requested"
      assert Email.email_excluded?("test@example.com")
    end

    test "excludes email without reason" do
      assert {:ok, exclusion} = Email.exclude_email("test@example.com")
      assert exclusion.email == "test@example.com"
      assert is_nil(exclusion.reason)
      assert Email.email_excluded?("test@example.com")
    end

    test "returns error for invalid email" do
      assert {:error, changeset} = Email.exclude_email("invalid-email")
      refute changeset.valid?
    end
  end

  describe "unexclude_email/1" do
    setup do
      {:ok, exclusion} = Email.exclude_email("test@example.com", "Test exclusion")
      {:ok, exclusion: exclusion}
    end

    test "removes email from exclusion list", %{exclusion: exclusion} do
      assert {:ok, removed_exclusion} = Email.unexclude_email("test@example.com")
      assert removed_exclusion.id == exclusion.id
      refute Email.email_excluded?("test@example.com")
    end

    test "returns error for non-excluded email" do
      assert {:error, :not_found} = Email.unexclude_email("nonexistent@example.com")
    end
  end

  describe "list_excluded_emails/0" do
    test "returns empty list when no exclusions exist" do
      assert Email.list_excluded_emails() == []
    end

    test "returns all excluded emails" do
      Email.exclude_email("test1@example.com", "Reason 1")
      Email.exclude_email("test2@example.com", "Reason 2")
      Email.exclude_email("test3@example.com")

      exclusions = Email.list_excluded_emails()
      assert length(exclusions) == 3

      emails = Enum.map(exclusions, & &1.email)
      assert "test1@example.com" in emails
      assert "test2@example.com" in emails
      assert "test3@example.com" in emails
    end
  end

  describe "get_email_exclusion/1" do
    setup do
      {:ok, exclusion} = Email.exclude_email("test@example.com", "Test exclusion")
      {:ok, exclusion: exclusion}
    end

    test "returns exclusion by ID", %{exclusion: exclusion} do
      found_exclusion = Email.get_email_exclusion(exclusion.id)
      assert found_exclusion.id == exclusion.id
      assert found_exclusion.email == "test@example.com"
    end

    test "returns nil for non-existent ID" do
      assert Email.get_email_exclusion(99999) == nil
    end
  end

  describe "update_email_exclusion/2" do
    setup do
      {:ok, exclusion} = Email.exclude_email("test@example.com", "Original reason")
      {:ok, exclusion: exclusion}
    end

    test "updates exclusion", %{exclusion: exclusion} do
      new_attrs = %{reason: "Updated reason"}
      assert {:ok, updated_exclusion} = Email.update_email_exclusion(exclusion, new_attrs)
      assert updated_exclusion.reason == "Updated reason"
      assert updated_exclusion.email == "test@example.com"
    end

    test "validates updated attributes", %{exclusion: exclusion} do
      invalid_attrs = %{email: "invalid-email"}
      assert {:error, changeset} = Email.update_email_exclusion(exclusion, invalid_attrs)
      refute changeset.valid?
    end
  end
end
