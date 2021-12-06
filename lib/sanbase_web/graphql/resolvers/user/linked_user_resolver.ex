defmodule SanbaseWeb.Graphql.Resolvers.LinkedUserResolver do
  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts.{LinkedUser, LinkedUserCandidate}

  require Logger

  def create_linked_users_token(_root, args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUserCandidate.create(user.id, args.secondary_user_id)
  end

  def confirm_linked_users_token(_root, args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUserCandidate.confirm_candidate(args.token, user.id)
  end

  def list_secondary_users(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUser.list_secondary_users(user.id)
  end

  def get_primary_user(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUser.get_primary_user(user.id)
  end

  def remove_secondary_user(_root, args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUser.remove_secondary_user(user.id, args.secondary_user_id)
  end

  def remove_primary_user(_root, args, %{context: %{auth: %{current_user: user}}}) do
    LinkedUser.remove_secondary_user(args.primary_user_id, user.id)
  end
end
