defmodule Sanbase.Email.EmailExclusionListTest do
  use Sanbase.DataCase

  alias Sanbase.Email.EmailExclusionList

  @valid_attrs %{email: "test@example.com", reason: "Unsubscribed"}
  @invalid_attrs %{email: "invalid-email", reason: nil}

  describe "changeset/2" do
    test "valid changeset with email and reason" do
      changeset = EmailExclusionList.changeset(%EmailExclusionList{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid changeset with email only" do
      attrs = %{email: "test@example.com"}
      changeset = EmailExclusionList.changeset(%EmailExclusionList{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without email" do
      attrs = %{reason: "Some reason"}
      changeset = EmailExclusionList.changeset(%EmailExclusionList{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "invalid changeset with invalid email format" do
      changeset = EmailExclusionList.changeset(%EmailExclusionList{}, @invalid_attrs)
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end
  end

  describe "is_excluded?/1" do
    setup do
      {:ok, exclusion} =
        EmailExclusionList.add_exclusion("excluded@example.com", "Test exclusion")

      {:ok, exclusion: exclusion}
    end

    test "returns true for excluded email" do
      assert EmailExclusionList.is_excluded?("excluded@example.com")
    end

    test "returns false for non-excluded email" do
      refute EmailExclusionList.is_excluded?("allowed@example.com")
    end

    test "returns false for invalid input" do
      refute EmailExclusionList.is_excluded?(nil)
      refute EmailExclusionList.is_excluded?(123)
      refute EmailExclusionList.is_excluded?("")
    end
  end

  describe "add_exclusion/2" do
    test "adds an email to exclusion list with reason" do
      assert {:ok, exclusion} =
               EmailExclusionList.add_exclusion("test@example.com", "User requested")

      assert exclusion.email == "test@example.com"
      assert exclusion.reason == "User requested"
    end

    test "adds an email to exclusion list without reason" do
      assert {:ok, exclusion} = EmailExclusionList.add_exclusion("test@example.com")
      assert exclusion.email == "test@example.com"
      assert is_nil(exclusion.reason)
    end

    test "prevents duplicate emails" do
      EmailExclusionList.add_exclusion("test@example.com", "First reason")

      assert {:error, changeset} =
               EmailExclusionList.add_exclusion("test@example.com", "Second reason")

      refute changeset.valid?
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "remove_exclusion/1" do
    setup do
      {:ok, exclusion} = EmailExclusionList.add_exclusion("test@example.com", "Test exclusion")
      {:ok, exclusion: exclusion}
    end

    test "removes an existing exclusion", %{exclusion: exclusion} do
      assert {:ok, removed_exclusion} = EmailExclusionList.remove_exclusion("test@example.com")
      assert removed_exclusion.id == exclusion.id
      refute EmailExclusionList.is_excluded?("test@example.com")
    end

    test "returns error for non-existent email" do
      assert {:error, :not_found} = EmailExclusionList.remove_exclusion("nonexistent@example.com")
    end
  end

  describe "list_exclusions/0" do
    test "returns empty list when no exclusions exist" do
      assert EmailExclusionList.list_exclusions() == []
    end

    test "returns all exclusions" do
      EmailExclusionList.add_exclusion("test1@example.com", "Reason 1")
      EmailExclusionList.add_exclusion("test2@example.com", "Reason 2")
      EmailExclusionList.add_exclusion("test3@example.com")

      exclusions = EmailExclusionList.list_exclusions()
      assert length(exclusions) == 3

      emails = Enum.map(exclusions, & &1.email)
      assert "test1@example.com" in emails
      assert "test2@example.com" in emails
      assert "test3@example.com" in emails
    end
  end

  describe "get_exclusion/1" do
    setup do
      {:ok, exclusion} = EmailExclusionList.add_exclusion("test@example.com", "Test exclusion")
      {:ok, exclusion: exclusion}
    end

    test "returns exclusion by ID", %{exclusion: exclusion} do
      found_exclusion = EmailExclusionList.get_exclusion(exclusion.id)
      assert found_exclusion.id == exclusion.id
      assert found_exclusion.email == "test@example.com"
    end

    test "returns nil for non-existent ID" do
      assert EmailExclusionList.get_exclusion(99999) == nil
    end
  end

  describe "update_exclusion/2" do
    setup do
      {:ok, exclusion} = EmailExclusionList.add_exclusion("test@example.com", "Original reason")
      {:ok, exclusion: exclusion}
    end

    test "updates exclusion reason", %{exclusion: exclusion} do
      new_attrs = %{reason: "Updated reason"}
      assert {:ok, updated_exclusion} = EmailExclusionList.update_exclusion(exclusion, new_attrs)
      assert updated_exclusion.reason == "Updated reason"
      assert updated_exclusion.email == "test@example.com"
    end

    test "validates email format on update", %{exclusion: exclusion} do
      invalid_attrs = %{email: "invalid-email"}
      assert {:error, changeset} = EmailExclusionList.update_exclusion(exclusion, invalid_attrs)
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end
  end
end
