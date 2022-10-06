defmodule SanbaseWeb.UserController do
  use SanbaseWeb, :controller

  alias Sanbase.Accounts.User
  alias SanbaseWeb.Router.Helpers, as: Routes

  def index(conn, users) do
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
      belongs_to: belongs_to(user)
    )
  end

  def reset_api_call_limits(conn, %{"id" => id}) do
    {:ok, user} = Sanbase.Math.to_integer(id) |> User.by_id()

    Sanbase.ApiCallLimit.update_usage_db(:user, user, 0)

    render(conn, "show.html",
      user: user,
      string_fields: string_fields(User),
      belongs_to: belongs_to(user)
    )
  end

  def belongs_to(user) do
    {:ok, acl} = Sanbase.ApiCallLimit.get_quota_db(:user, user)

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
    fields =
      module
      |> fields()

    # |> Enum.filter(fn field -> module.__schema__(:type, field) in [:string, :naive_datetime, :utc_datetime] end)
    # [:id] ++ fields
  end
end
