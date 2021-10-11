defmodule SanbaseWeb.ExAdmin.Accounts.User do
  use ExAdmin.Register

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Insight.Post

  register_resource Sanbase.Accounts.User do
    controller do
      before_filter(:assign_all_user_insights_to_anonymous, only: [:destroy])
    end

    index do
      column(:id)
      column(:username)
      column(:email)
      column(:twitter_id)
      column(:is_superuser)
      column(:san_balance)
    end

    show user do
      attributes_table(all: true)

      panel "User Settings" do
        table_for [Sanbase.Repo.preload(user, [:user_settings]).user_settings] do
          column(:id, link: true)
        end
      end

      panel "Apikey tokens" do
        table_for Sanbase.Accounts.UserApikeyToken.user_tokens_structs(user) |> elem(1) do
          column(:token, link: true)
        end
      end

      panel "Subscriptions" do
        table_for Sanbase.Repo.preload(user, [
                    :subscriptions,
                    subscriptions: [:plan, plan: :product]
                  ]).subscriptions do
          column(:id, link: true)
          column(:status)

          column(:subscription, fn subscription ->
            "#{subscription.plan.name}/#{subscription.plan.product.name |> String.trim_trailing(" by Santiment")}"
          end)
        end
      end

      panel "Last 10 Published Insights" do
        table_for Sanbase.Insight.Post.user_public_insights(user.id, page: 1, page_size: 10) do
          column(:id, link: true)
          column(:title, link: true)
        end
      end

      panel "ETH Accounts" do
        table_for user.eth_accounts do
          column(:id, link: true)
          column(:address)

          column("San balance", fn eth_account ->
            case EthAccount.san_balance(eth_account) do
              :error -> ""
              san_balance -> san_balance
            end
          end)
        end
      end
    end

    form user do
      inputs do
        input(user, :is_superuser)
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
