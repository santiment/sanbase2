defmodule SanbaseWeb.Graphql.Resolvers.LinkedUserResolver do
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Product, Subscription}
  alias Sanbase.Accounts.{LinkedUser, LinkedUserCandidate}
  import SanbaseWeb.Graphql.Helpers.UserPublicIdHelper, only: [resolve_user_id: 3]

  def generate_linked_users_token(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with {:ok, secondary_user_id} <-
           resolve_user_id(args, :secondary_user_id, :secondary_user_public_id),
         {:ok, %{token: token}} <- LinkedUserCandidate.create(user.id, secondary_user_id) do
      {:ok, token}
    end
  end

  def confirm_linked_users_token(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with :ok <- LinkedUserCandidate.confirm_candidate(args.token, user.id) do
      {:ok, true}
    end
  end

  def get_secondary_users(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUser.get_secondary_users(user.id)
  end

  def get_primary_user(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUser.get_primary_user(user.id)
  end

  def primary_user_sanbase_subscription(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    Subscription.get_user_subscription(user.id, Product.product_sanbase())
  end

  def primary_user_sanbase_subscription(%User{} = user, _args, _resolution) do
    Subscription.get_user_subscription(user.id, Product.product_sanbase())
  end

  def primary_user_sanbase_subscription(_root, _args, %{source: %{user: user}}) do
    Subscription.get_user_subscription(user.id, Product.product_sanbase())
  end

  def remove_secondary_user(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with {:ok, secondary_user_id} <-
           resolve_user_id(args, :secondary_user_id, :secondary_user_public_id),
         :ok <- LinkedUser.remove_linked_user_pair(user.id, secondary_user_id) do
      {:ok, true}
    end
  end

  def remove_primary_user(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with {:ok, primary_user_id} <-
           resolve_user_id(args, :primary_user_id, :primary_user_public_id),
         :ok <- LinkedUser.remove_linked_user_pair(primary_user_id, user.id) do
      {:ok, true}
    end
  end
end
