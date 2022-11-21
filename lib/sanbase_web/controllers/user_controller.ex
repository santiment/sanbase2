defmodule SanbaseWeb.UserController do
  use SanbaseWeb, :controller

  alias Sanbase.Accounts.User

  def index(conn, _params) do
    users = User.all_users()
    render(conn, "index.html", users: users)
  end

  def search(conn, %{"user_search" => %{"user_search" => search_text}}) do
    users =
      case Integer.parse(search_text) do
        {user_id, ""} -> search_by_id(user_id)
        _ -> search_by_text(String.downcase(search_text))
      end

    render(conn, "index.html", users: users)
  end

  def show(conn, %{"id" => id}) do
    {:ok, user} = Sanbase.Math.to_integer(id) |> User.by_id()

    render(conn, "show.html",
      user: user,
      string_fields: string_fields(User),
      belongs_to: belongs_to(user),
      has_many: has_many(user)
    )
  end

  def reset_api_call_limits(conn, %{"id" => id}) do
    {:ok, user} = Sanbase.Math.to_integer(id) |> User.by_id()

    Sanbase.ApiCallLimit.reset(user)

    show(conn, %{"id" => user.id})
  end

  def has_many(user) do
    user =
      user |> Sanbase.Repo.preload([:eth_accounts, :posts, subscriptions: [plan: [:product]]])

    [
      %{
        model: "Subscriptions",
        rows: user.subscriptions,
        fields: [:id, :plan, :status],
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
        name: "Api calls used",
        fields: [
          %{
            field_name: "Api calls used",
            data: api_calls_count
          }
        ],
        actions: []
      }
    ]
  end

  defp search_by_text(text) do
    User.by_search_text(text)
  end

  defp search_by_id(user_id) do
    case Sanbase.Accounts.get_user(user_id) do
      {:ok, user} -> [user]
      _ -> []
    end
  end

  def fields(module) do
    module.__schema__(:fields)
  end

  defp string_fields(module) do
    module
    |> fields()

    # |> Enum.filter(fn field -> module.__schema__(:type, field) in [:string, :naive_datetime, :utc_datetime] end)
    # |> List.insert_at(0, [:id])
  end
end
