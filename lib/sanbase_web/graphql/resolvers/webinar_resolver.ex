defmodule SanbaseWeb.Graphql.Resolvers.WebinarResolver do
  @moduledoc false
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Webinar
  alias Sanbase.Webinars.Registration

  require Logger

  def get_webinars(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    plan =
      user
      |> Subscription.current_subscription(Product.product_sanbase())
      |> Subscription.plan_name()

    {:ok, Webinar.get_all(%{is_logged_in: true, plan_name: plan})}
  end

  def get_webinars(_root, _args, _resolution) do
    {:ok, Webinar.get_all(%{is_logged_in: false})}
  end

  def register_for_webinar(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{user_id: user.id, webinar_id: args.webinar_id}
    |> Registration.create()
    |> case do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end
end
