defmodule SanbaseWeb.Graphql.UserSettingsTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.UserSettingsResolver

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
    field(:is_subscribed_edu_emails, :boolean)
    field(:is_subscribed_monthly_newsletter, :boolean)
    field(:is_subscribed_biweekly_report, :boolean)
    field(:is_subscribed_marketing_emails, :boolean)
    field(:is_subscribed_comments_emails, :boolean)
    field(:is_subscribed_likes_emails, :boolean)

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
    field(:is_subscribed_marketing_emails, :boolean)
    field(:is_subscribed_comments_emails, :boolean)
    field(:is_subscribed_likes_emails, :boolean)

    # Deprecated fields
    field(:signal_notify_telegram, :boolean)
    field(:signal_notify_email, :boolean)
    field(:signals_per_day_limit, :json)
  end
end
