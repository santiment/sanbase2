defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Tag
  alias Sanbase.UserList
  alias Sanbase.Auth.{User, UserSettings}
  alias Sanbase.Insight.{Post, Poll}
  alias Sanbase.Model.{Project, ExchangeAddress, ProjectEthAddress}
  alias Sanbase.Signals.{UserTrigger, HistoricalActivity}

  def user_factory() do
    %User{
      salt: User.generate_salt(),
      privacy_policy_accepted: true
    }
  end

  def insights_fallback_user_factory() do
    %User{
      salt: User.generate_salt(),
      username: User.insights_fallback_username(),
      email: User.insights_fallback_email()
    }
  end

  def staked_user_factory() do
    %User{
      salt: User.generate_salt(),
      san_balance: Decimal.new(20000),
      san_balance_updated_at: Timex.now(),
      privacy_policy_accepted: true
    }
  end

  def poll_factory() do
    %Poll{
      start_at: DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC"),
      end_at: DateTime.from_naive!(~N[2030-05-13 00:00:00], "Etc/UTC")
    }
  end

  def post_factory() do
    %Post{
      user: build(:user),
      poll: build(:poll),
      title: "Awesome analysis",
      link: "http://example.com",
      text: "Text of the post",
      state: Post.awaiting_approval_state()
    }
  end

  def post_no_default_user_factory() do
    %Post{
      title: "Awesome analysis",
      link: "http://example.com",
      text: "Text of the post",
      state: Post.awaiting_approval_state()
    }
  end

  def tag_factory() do
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
      infrastructure: nil,
      eth_addresses: [build(:project_eth_address)]
    }
  end

  def project_eth_address_factory() do
    %ProjectEthAddress{
      address: "0x" <> (:crypto.strong_rand_bytes(16) |> Base.encode16()),
      source: "",
      comments: ""
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
        signal_notify_email: false,
        newsletter_subscription: "OFF"
      }
    }
  end

  def user_trigger_factory() do
    %UserTrigger{
      user: build(:user),
      trigger: %{
        title: "Generic title"
      }
    }
  end

  def signals_historical_activity_factory() do
    %HistoricalActivity{
      user_trigger: %{}
    }
  end

  def watchlist_factory() do
    %UserList{name: "Generic User List name", color: :red, user: build(:user)}
  end
end
