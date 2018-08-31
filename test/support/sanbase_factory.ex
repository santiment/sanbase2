defmodule Sanbase.Factory do
  use ExMachina.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.User

  def user_factory do
    %User{
      salt: User.generate_salt(),
    }
  end

  def staked_user_factory do
    %User{
      salt: User.generate_salt(),
      san_balance: Decimal.new(20000),
      san_balance_updated_at: Timex.now()
    }
  end
end
