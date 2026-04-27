defmodule SanbaseWeb.Graphql.Resolvers.UserOnboardingResolver do
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias Sanbase.Accounts.{User, UserOnboarding}

  def user_onboarding(%User{id: user_id}, _args, _resolution) do
    {:ok, UserOnboarding.for_user(user_id)}
  end

  def submit_user_onboarding(_root, %{onboarding: attrs}, %{
        context: %{auth: %{current_user: %User{id: user_id}}}
      }) do
    case UserOnboarding.upsert(user_id, attrs) do
      {:ok, onboarding} ->
        {:ok, onboarding}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Cannot submit user onboarding. Reason: #{changeset_errors_string(changeset)}"}
    end
  end
end
