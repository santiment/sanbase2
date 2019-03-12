defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Tag
  alias Sanbase.Auth.{User, UserSettings}
  alias Sanbase.Insight.{Post, Poll}
  alias Sanbase.Model.{Project, ExchangeAddress}
  alias Sanbase.Signals.{UserTrigger, HistoricalActivity}

  def user_factory do
    %User{
      salt: User.generate_salt(),
      privacy_policy_accepted: true
    }
  end

  def insights_fallback_user_factory do
    %User{
      salt: User.generate_salt(),
      username: User.insights_fallback_username(),
      email: User.insights_fallback_email()
    }
  end

  def staked_user_factory do
    %User{
      salt: User.generate_salt(),
      san_balance: Decimal.new(20000),
      san_balance_updated_at: Timex.now()
    }
  end

  def post_factory do
    %Post{
      user_id: build(:user),
      title: "Awesome analysis",
      link: "http://example.com",
      text: "Text of the post",
      state: Post.approved_state()
    }
  end

  def tag_factory do
    %Tag{
      name: "SAN"
    }
  end

  def project_factory() do
    %Project{
      name: "Santiment",
      ticker: "SAN",
      coinmarketcap_id: "santiment",
      token_decimals: 18,
      total_supply: 83_000_000,
      github_link: "https://github.com/santiment",
      infrastructure: nil
    }
  end

  def exchange_address_factory() do
    %ExchangeAddress{
      address: "0x123",
      name: "Binance"
    }
  end

  def user_settings_factory() do
    %UserSettings{
      settings: %{
        signal_notify_telegram: false,
        signal_notify_email: false
      }
    }
  end

  def user_triggers_factory() do
    %UserTrigger{
      trigger: %{}
    }
  end

  def signals_historical_activity_factory() do
    %HistoricalActivity{
      user_trigger: %{}
    }
  end
end
