defmodule SanbaseWeb.GenericAdmin.User do
  alias Sanbase.Accounts.User
  alias SanbaseWeb.GenericController

  @resource %{
    "users" => %{
      module: User,
      admin_module: __MODULE__,
      singular: "user",
      index_fields: [:id, :name, :email, :username],
      edit_fields: [:stripe_customer_id, :email],
      show_fields: :all,
      actions: [:show, :edit]
    }
  }

  def resource, do: @resource

  def has_many(user) do
    user =
      user |> Sanbase.Repo.preload([:eth_accounts, :posts, subscriptions: [plan: [:product]]])

    [
      %{
        model: "Subscriptions",
        rows: user.subscriptions,
        fields: [:id, :plan, :status, :type],
        funcs: %{
          plan: fn s -> s.plan.product.name <> "/" <> s.plan.name end
        }
      },
      %{
        model: "Eth Accounts",
        rows: user.eth_accounts,
        fields: [:id, :address, :san_balance],
        funcs: %{
          plan: fn eth_account ->
            case Sanbase.Accounts.EthAccount.san_balance(eth_account) do
              :error -> 0.0
              san_balance -> san_balance
            end
          end
        }
      },
      %{
        model: "Last 10 Published Insights",
        rows: Sanbase.Insight.Post.user_public_insights(user.id, page: 1, page_size: 10),
        fields: [:id, :title],
        funcs: %{}
      },
      %{
        model: "Apikey tokens",
        rows: Sanbase.Accounts.UserApikeyToken.user_tokens_structs(user) |> elem(1),
        fields: [:id, :token],
        funcs: %{}
      }
    ]
  end

  def belongs_to(user) do
    {_, acl} = Sanbase.ApiCallLimit.get_quota_db(:user, user)

    api_calls_count =
      case Sanbase.Clickhouse.ApiCallData.api_call_count(
             user.id,
             Timex.beginning_of_month(Timex.now()),
             Timex.now(),
             :apikey
           ) do
        {:ok, api_calls_count} -> api_calls_count
        {:error, _} -> 0
      end

    {:ok, executions_details} = Sanbase.Queries.user_executions_summary(user.id)

    [
      %{
        name: "Api Calls Limits",
        fields: [
          %{
            field_name: "api calls limits",
            data: inspect(acl, pretty: true)
          }
        ],
        actions: [:reset_api_call_limits]
      },
      %{
        name: "Api Calls Used",
        fields: [
          %{
            field_name: "Api Calls Used",
            data: api_calls_count
          }
        ],
        actions: []
      },
      %{
        name: "Queries Resources Spent",
        fields: [
          %{
            field_name: "Queries Resources Spent",
            data: inspect(executions_details, pretty: true)
          }
        ],
        actions: [:reset_queries_credits_spent]
      },
      %{
        name: "SAN Staked in LP SAN/ETH",
        fields: [
          %{
            field_name: "Eligible for free Liquidity Subscription",
            data:
              Sanbase.Billing.Subscription.LiquiditySubscription.eligible_for_liquidity_subscription?(
                user.id
              )
          },
          %{
            field_name: "SAN Staked",
            data: Sanbase.Accounts.User.UniswapStaking.fetch_uniswap_san_staked_user(user.id)
          }
        ],
        actions: []
      }
    ]
  end

  def reset_api_call_limits(conn, %{id: id}) do
    {:ok, user} = Sanbase.Math.to_integer(id) |> User.by_id()

    Sanbase.ApiCallLimit.reset(user)

    GenericController.show(conn, %{"resource" => "users", "id" => user.id})
  end

  def reset_queries_credits_spent(conn, %{id: user_id}) do
    Sanbase.Math.to_integer(user_id)
    |> Sanbase.ModeratorQueries.reset_user_monthly_credits()

    GenericController.show(conn, %{"resource" => "users", "id" => user_id})
  end

  defimpl String.Chars, for: Map do
    def to_string(map) do
      inspect(map)
    end
  end
end
