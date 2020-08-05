defmodule SanbaseWeb.Graphql.Schema.IntercomQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.BasicAuth

  object :user_attributes do
    field(:user_id, :id)
    field(:inserted_at, :datetime)
    field(:properties, :json)
  end

  object :intercom_queries do
    @desc ~s"""
    Get user attributes over time.
    Args:
    * `users`: List of integer user ids
    * `days`: Historical days, default: 30

    or alternatively:
    * from: start datetime, default: `days` arg
    * to: end datetime, default: now
    """
    field :get_attributes_for_users, list_of(:user_attributes) do
      arg(:users, non_null(list_of(:id)))
      arg(:days, non_null(:integer), default_value: 30)
      arg(:from, :datetime)
      arg(:to, :datetime)

      middleware(BasicAuth)

      resolve(fn _, %{users: users, days: days} = args, _ ->
        from = Map.get(args, :from, Sanbase.DateTimeUtils.days_ago(days))
        to = Map.get(args, :to, Timex.now())

        {:ok, Sanbase.Intercom.UserAttributes.get_attributes_for_users(users, from, to)}
      end)
    end
  end
end
