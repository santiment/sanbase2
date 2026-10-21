defmodule Sanbase.Billing.BusinessClients.SettingsTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Billing.BusinessClients.Settings
  alias Sanbase.Repo

  test "stores only the changed keys, so the others keep following their defaults" do
    assert {:ok, %{churn_window_months: 6}} = Settings.update(%{churn_window_months: 6}, nil)

    assert %Settings{settings: stored} = Repo.get_by!(Settings, key: "default")
    assert stored == %{"churn_window_months" => 6}

    assert {:ok, settings} = Settings.update(%{renewal_grace_days: 10}, nil)
    assert settings.churn_window_months == 6
    assert settings.renewal_grace_days == 10
    assert settings.issue_types == Settings.defaults().issue_types

    assert %Settings{settings: stored} = Repo.get_by!(Settings, key: "default")
    assert stored == %{"churn_window_months" => 6, "renewal_grace_days" => 10}
  end

  test "lowercases the free email domains" do
    assert {:ok, settings} = Settings.update(%{free_email_domains: "Gmail.com, ACME.io"}, nil)
    assert settings.free_email_domains == ["gmail.com", "acme.io"]
  end
end
