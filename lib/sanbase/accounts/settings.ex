defmodule Sanbase.Accounts.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @default_alerts_limit_per_day %{
    "email" => 50,
    "telegram" => 100,
    "telegram_channel" => 1000,
    "webhook" => 1000,
    "webpush" => 1000
  }

  def default_alerts_limit_per_day(), do: @default_alerts_limit_per_day

  embedded_schema do
    field(:hide_privacy_data, :boolean, default: true)
    field(:theme, :string, default: "default")
    field(:page_size, :integer, default: 20)
    field(:is_beta_mode, :boolean, default: false)
    field(:table_columns, :map, default: %{})
    field(:is_promoter, :boolean, default: false)
    field(:paid_with, :string, default: nil)
    field(:favorite_metrics, {:array, :string}, default: [])

    # Alerts settings
    field(:has_telegram_connected, :boolean, virtual: true)
    field(:telegram_chat_id, :integer)
    field(:alert_notify_email, :boolean, default: false)
    field(:alert_notify_telegram, :boolean, default: false)
    field(:alerts_per_day_limit, :map, default: %{})
    field(:alerts_fired, :map, default: %{})

    # Email settings

    # 1. Emails sent through Sanbase
    field(:is_subscribed_edu_emails, :boolean, default: true)
    field(:is_subscribed_marketing_emails, :boolean, default: false)
    field(:is_subscribed_comments_emails, :boolean, default: true)
    field(:is_subscribed_likes_emails, :boolean, default: true)

    # 2. Email campaigns/lists through Mailchimp
    field(:is_subscribed_monthly_newsletter, :boolean, default: true)
    field(:is_subscribed_biweekly_report, :boolean, default: false)
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [
      :theme,
      :page_size,
      :is_beta_mode,
      :table_columns,
      :alert_notify_email,
      :alert_notify_telegram,
      :telegram_chat_id,
      :hide_privacy_data,
      :is_promoter,
      :paid_with,
      :favorite_metrics,
      :alerts_per_day_limit,
      :alerts_fired,
      :is_subscribed_edu_emails,
      :is_subscribed_monthly_newsletter,
      :is_subscribed_biweekly_report,
      :is_subscribed_marketing_emails,
      :is_subscribed_comments_emails,
      :is_subscribed_likes_emails
    ])
  end

  def get_alerts_limit_per_day(%__MODULE__{} = settings, channel) do
    limits =
      case settings.alerts_per_day_limit do
        map when map_size(map) == 0 -> @default_alerts_limit_per_day
        map -> map
      end

    limits[channel] |> Sanbase.Math.to_integer()
  end

  def get_alerts_fired_today(%__MODULE__{} = settings, channel) do
    today_str = Date.utc_today() |> to_string()
    settings.alerts_fired[today_str][channel] |> Sanbase.Math.to_integer() || 0
  end
end
