defmodule SanbaseWeb.Graphql.Resolvers.WebinarResolver do
  require Logger

  alias Sanbase.Webinar
  alias Sanbase.Webinars.Registration
  alias Sanbase.Billing.{Subscription, Product}

  def get_webinars(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    plan =
      Subscription.current_subscription(user, Product.product_sanbase())
      |> Subscription.plan_name()

    {:ok, Webinar.get_all(%{is_logged_in: true, plan_name: plan})}
  end

  def get_webinars(_root, _args, _resolution) do
    {:ok, Webinar.get_all(%{is_logged_in: false})}
  end

  def register_for_webinar(_root, args, %{context: %{auth: %{current_user: user}}}) do
    Registration.create(%{user_id: user.id, webinar_id: args.webinar_id})
    |> case do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end
end
