defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Post, Poll}
  alias Sanbase.Model.Project

  def user_factory do
    %User{
      salt: User.generate_salt()
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
end
