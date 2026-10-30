defmodule SanbaseWeb.Graphql.Resolvers.WebinarResolver do
  alias Sanbase.Webinars.{Webinar, Registration}
  alias Sanbase.Billing

  def get_webinars(_root, _args, %{context: %{auth: %{current_user: _} = auth}}) do
    has_pro_access = Billing.sanbase_pro_access_from_auth?(auth)

    {:ok, Webinar.get_all(%{is_logged_in: true, has_pro_access: has_pro_access})}
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
