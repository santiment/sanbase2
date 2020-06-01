defmodule Sanbase.ExAdmin.Auth.User do
  use ExAdmin.Register

  alias Sanbase.Auth.EthAccount
  alias Sanbase.Insight.Post

  register_resource Sanbase.Auth.User do
    controller do
      before_filter(:assign_all_user_insights_to_anonymous, only: [:destroy])
    end

    show user do
      attributes_table(all: true)

      panel "Eth accounts" do
        table_for user.eth_accounts do
          column(:id, link: true)
          column(:address)

          column("San balance", fn eth_account ->
            case EthAccount.san_balance(eth_account) do
              :error -> ""
              san_balance -> san_balance || ""
            end
          end)
        end
      end
    end

    form user do
      inputs do
        input(user, :test_san_balance)
        input(user, :email)
        input(user, :stripe_customer_id)
      end
    end
  end

  def assign_all_user_insights_to_anonymous(conn, params) do
    Post.assign_all_user_insights_to_anonymous(params[:id])

    {conn, params}
  end
end
