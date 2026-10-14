defmodule Sanbase.Email.ListImportTest do
  use Sanbase.DataCase, async: false

  import Mox
  import Sanbase.Factory

  alias Sanbase.Accounts.{User, UserSettings}
  alias Sanbase.Email.{ListConsent, ListImport}
  alias Sanbase.Repo

  setup :set_mox_global

  setup do
    stub(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ ->
      flunk("Mailjet must not be called")
    end)

    stub(Sanbase.Email.MockMailjetApi, :unsubscribe, fn _, _ ->
      flunk("Mailjet must not be called")
    end)

    on_list = insert(:user, email: "On.List@example.com", marketing_accepted: false)
    off_list = insert(:user, email: "off-list@example.com", marketing_accepted: true)
    insert(:user_settings, user: off_list, settings: %{is_subscribed_weekly_newsletter: true})
    unchanged = insert(:user, email: "unchanged@example.com")

    stub(Sanbase.Email.MockMailjetApi, :fetch_list_subscribed_emails, fn :marketing_newsletter ->
      {:ok, ["on.list@example.com", "unchanged-not-a-user@example.com"]}
    end)

    %{on_list: on_list, off_list: off_list, unchanged: unchanged}
  end

  test "a dry run only counts the changes", %{on_list: on_list} do
    assert {:ok, %{dry_run: true, mailjet_subscribed: 2, to_subscribe: 1, to_unsubscribe: 1}} =
             ListImport.import_from_mailjet(:newsletter)

    refute newsletter?(on_list)
    assert [] = ListConsent.history(on_list.id, :newsletter)
  end

  test "makes the newsletter setting match Mailjet without calling it", context do
    %{on_list: on_list, off_list: off_list, unchanged: unchanged} = context

    assert {:ok, %{dry_run: false, to_subscribe: 1, to_unsubscribe: 1, failed: []}} =
             ListImport.import_from_mailjet(:newsletter, dry_run: false)

    assert newsletter?(on_list)
    refute newsletter?(off_list)
    refute newsletter?(unchanged)

    assert [%ListConsent{subscribed: true, source: :mailjet_list_import}] =
             ListConsent.history(on_list.id, :newsletter)

    assert [%ListConsent{subscribed: false, source: :mailjet_list_import}] =
             ListConsent.history(off_list.id, :newsletter)

    assert [] = ListConsent.history(unchanged.id, :newsletter)

    # The marketing consent is not changed
    refute Repo.get!(User, on_list.id).marketing_accepted
    assert Repo.get!(User, off_list.id).marketing_accepted
  end

  test "refuses an empty Mailjet list", %{off_list: off_list} do
    stub(Sanbase.Email.MockMailjetApi, :fetch_list_subscribed_emails, fn _ -> {:ok, []} end)

    assert {:error, :empty_mailjet_list} =
             ListImport.import_from_mailjet(:newsletter, dry_run: false)

    assert newsletter?(off_list)
  end

  defp newsletter?(user) do
    UserSettings.settings_for(user, force: true).is_subscribed_weekly_newsletter
  end
end
