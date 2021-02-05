defmodule SanbaseWeb.Graphql.UserSettingsTypes do
  use Absinthe.Schema.Notation

  enum :newsletter_subscription_type do
    value(:weekly)
    value(:daily)
    value(:off)
  end

  object :user_settings do
    field(:hide_privacy_data, :boolean)
    field(:is_beta_mode, :boolean)
    field(:is_promoter, :boolean)
    field(:theme, :string)
    field(:page_size, :integer)
    field(:table_columns, :json)
    field(:newsletter_subscription, :newsletter_subscription_type)
    field(:has_telegram_connected, :boolean)
    field(:paid_with, :string)
    field(:alert_notify_email, :boolean)
    field(:alert_notify_telegram, :boolean)
    field(:alerts_per_day_limit, :json)
    # Deprecated fields
    field :signal_notify_telegram, :boolean do
      resolve(fn settings, _, _ -> {:ok, settings.alert_notify_telegram} end)
    end

    field :signal_notify_email, :boolean do
      resolve(fn settings, _, _ -> {:ok, settings.alert_notify_email} end)
    end

    field :signals_per_day_limit, :json do
      resolve(fn settings, _, _ -> {:ok, settings.alerts_per_day_limit} end)
    end
  end

  input_object :user_settings_input_object do
    field(:hide_privacy_data, :boolean)
    field(:is_beta_mode, :boolean)
    field(:theme, :string)
    field(:page_size, :integer)
    field(:table_columns, :json)
    field(:newsletter_subscription, :newsletter_subscription_type)
    field(:has_telegram_connected, :boolean)
    field(:alert_notify_email, :boolean)
    field(:alert_notify_telegram, :boolean)
    field(:alerts_per_day_limit, :json)
    # Deprecated fields
    field(:signal_notify_telegram, :boolean)
    field(:signal_notify_email, :boolean)
    field(:signals_per_day_limit, :json)
  end
end
