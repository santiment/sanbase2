defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.User
  alias Sanbase.Voting.{Post, Poll}

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
end
