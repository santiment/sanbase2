defmodule SanbaseWeb.GenericAdmin.User do
  alias Sanbase.Accounts.User
  alias SanbaseWeb.GenericController

  @schema_module User

  def schema_module, do: @schema_module

  def resource do
    %{
      actions: [:edit],
      index_fields: [:id, :username, :email, :twitter_id, :is_superuser, :san_balance],
      edit_fields: [:is_superuser, :test_san_balance, :email, :stripe_customer_id]
    }
  end

  def has_many(user) do
    user =
      user
      |> Sanbase.Repo.preload([
        :eth_accounts,
        :user_settings,
        :posts,
        subscriptions: [plan: [:product]]
      ])

    [
      %{
        resource: "subscriptions",
        resource_name: "Subscriptions",
        rows: user.subscriptions,
        fields: [
          :id,
          :stripe_id,
          :plan,
          :status,
          :type,
          :current_period_end,
          :trial_end,
          :cancel_at_period_end,
          :inserted_at,
          :updated_at
        ],
        funcs: %{
          plan: fn s -> s.plan.product.name <> "/" <> s.plan.name end
        },
        create_link_kv: []
      },
      %{
        resource: "eth_accounts",
        resource_name: "Eth Accounts",
        rows: user.eth_accounts,
        fields: [:id, :address, :san_balance],
        funcs: %{
          plan: fn eth_account ->
            case Sanbase.Accounts.EthAccount.san_balance(eth_account) do
              :error -> +0.0
              san_balance -> san_balance
            end
          end
        },
        create_link_kv: []
      },
      %{
        resource: "posts",
        resource_name: "Last 10 Published Insights",
        rows: Sanbase.Insight.Post.user_public_insights(user.id, page: 1, page_size: 10),
        fields: [:id, :title, :published_at],
        funcs: %{},
        create_link_kv: []
      },
      %{
        resource: "user_apikey_tokens",
        resource_name: "Apikey tokens",
        rows: Sanbase.Accounts.UserApikeyToken.user_tokens_structs(user) |> elem(1),
        fields: [:id, :token],
        funcs: %{},
        create_link_kv: []
      },
      %{
        resource: "user_settings",
        resource_name: "User Settings",
        rows: if(user.user_settings, do: [user.user_settings], else: []),
        fields: [:id],
        funcs: %{},
        create_link_kv: []
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
            field_name: "SAN Staked",
            data: fetch_san_staked(user)
          }
        ],
        actions: []
      }
    ]
  end

  def fetch_san_staked(user) do
    try do
      Sanbase.Accounts.User.UniswapStaking.fetch_uniswap_san_staked_user(user.id)
    rescue
      _error -> 0.0
    end
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

  def user_link(row) do
    if row.user_id do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "users",
        row.user_id,
        row.user.email || row.user.username
      )
    else
      ""
    end
  end

  defimpl String.Chars, for: Map do
    def to_string(map) do
      inspect(map)
    end
  end
end

defmodule SanbaseWeb.GenericAdmin.UserSettings do
  @schema_module Sanbase.Accounts.UserSettings
  def schema_module(), do: @schema_module

  def resource do
    %{
      index_fields: [:id],
      funcs: %{
        settings: fn us ->
          Map.from_struct(us.settings) |> Map.delete(:alerts_fired) |> Jason.encode!(pretty: true)
        end
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.UserList do
  import Ecto.Query
  def schema_module(), do: Sanbase.UserList

  def resource do
    %{
      actions: [:edit],
      preloads: [:user],
      index_fields: [:id, :name, :slug, :type, :is_featured, :is_public, :user_id, :function],
      edit_fields: [:name, :slug, :description, :type, :is_public, :is_featured],
      search_fields: %{
        is_featured:
          from(
            ul in Sanbase.UserList,
            left_join: featured_item in Sanbase.FeaturedItem,
            on: ul.id == featured_item.user_list_id,
            where: not is_nil(featured_item.id),
            preload: [:user]
          )
          |> distinct(true)
      },
      extra_fields: [:is_featured],
      field_types: %{
        is_featured: :boolean
      },
      funcs: %{
        user_id: &SanbaseWeb.GenericAdmin.User.user_link/1,
        function: fn ul -> Map.from_struct(ul.function) |> Jason.encode!(pretty: true) end
      },
      collections: %{
        type: ~w[project blockchain_address]
      }
    }
  end

  def before_filter(user_list) do
    user_list = Sanbase.Repo.preload(user_list, [:featured_item])
    is_featured = if user_list.featured_item, do: true, else: false

    %{user_list | is_featured: is_featured}
  end

  def after_filter(user_list, params) do
    is_featured = params["is_featured"] |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(user_list, is_featured)
  end

  def user_list_link(row) do
    if row.user_list_id do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "user_lists",
        row.user_list_id,
        row.user_list.name
      )
    else
      ""
    end
  end
end
