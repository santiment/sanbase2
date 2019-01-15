defmodule Sanbase.ExAdmin.Auth.User do
  use ExAdmin.Register

  alias Sanbase.Auth.EthAccount
  alias Sanbase.Voting.Post

  @environment Mix.env()

  register_resource Sanbase.Auth.User do
    controller do
      before_filter(:assign_insights_anonymous, only: [:destroy])
    end

    show user do
      attributes_table()

      panel "Eth accounts" do
        table_for user.eth_accounts do
          column(:id, link: true)
          column(:address)

          unless @environment == :dev do
            column("San balance", fn eth_account ->
              case EthAccount.san_balance(eth_account) do
                nil -> ""
                san_balance -> san_balance |> Decimal.to_string()
              end
            end)
          end
        end
      end
    end

    form user do
      inputs do
        input(user, :test_san_balance)
        input(user, :email)
      end
    end
  end

  def assign_insights_anonymous(conn, params) do
    Post.change_owner_to_anonymous(params[:id])

    {conn, params}
  end
end
