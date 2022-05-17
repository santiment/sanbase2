defmodule SanbaseWeb.Graphql.UserSettingsTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.UserSettingsResolver

  enum :newsletter_subscription_type do
    value(:weekly)
    value(:daily)
    value(:off)
  end

  object :email_settings do
    field(:edu_emails, :email_setting_values)
    field(:monthly_newsletter, :email_setting_values)
    field(:biweekly_report, :email_setting_values)
  end

  object :email_setting_values do
    field(:is_subscribed, :boolean)
    field(:updated_at, :datetime)
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
    field(:email_settings, :email_settings)

    field :alerts_per_day_limit_left, :json do
      resolve(&UserSettingsResolver.alerts_per_dy_limit_left/3)
    end

    field(:favorite_metrics, list_of(:string))
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

  input_object :email_settings_input_object do
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
    field(:favorite_metrics, list_of(:string))
    field(:is_subscribed_edu_emails, :boolean)
    field(:is_subscribed_monthly_newsletter, :boolean)
    field(:is_subscribed_biweekly_report, :boolean)
    # Deprecated fields
    field(:signal_notify_telegram, :boolean)
    field(:signal_notify_email, :boolean)
    field(:signals_per_day_limit, :json)
  end
end
