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

  test "the risk thresholds default to the backtested values and can be changed" do
    assert %{
             risk_new_client_days: 92,
             risk_high_active_days: 7,
             risk_low_active_days: 15,
             risk_usage_drop_percent: 30,
             risk_renewal_days: 90
           } = Settings.get()

    assert {:ok, settings} =
             Settings.update(%{risk_high_active_days: 5, risk_usage_drop_percent: 50}, nil)

    assert settings.risk_high_active_days == 5
    assert settings.risk_usage_drop_percent == 50
    assert settings.risk_low_active_days == 15
  end

  test "rejects risk thresholds that make no sense" do
    assert {:error, changeset} = Settings.update(%{risk_usage_drop_percent: 0}, nil)
    assert errors_on(changeset).risk_usage_drop_percent != []

    # The High Risk bound of active days cannot be above the At Risk one.
    assert {:error, changeset} =
             Settings.update(%{risk_high_active_days: 20, risk_low_active_days: 10}, nil)

    assert errors_on(changeset).risk_low_active_days != []
    assert Settings.get().risk_high_active_days == 7
  end
end
