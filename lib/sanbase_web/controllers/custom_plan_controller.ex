defmodule SanbaseWeb.CustomPlanController do
  use SanbaseWeb, :controller

  alias Sanbase.Billing.Plan
  alias SanbaseWeb.Router.Helpers, as: Routes

  def index(conn, _params) do
    {:ok, custom_plans} = Plan.list_custom_plans()
    render(conn, "index.html", custom_plans: custom_plans)
  end

  def new(conn, _params) do
    changeset = Plan.changeset(%Plan{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"plan" => params}) do
    args = params_to_args(params)

    case Plan.create_custom_api_plan(args) do
      {:ok, custom_plan} ->
        _ =
          custom_plan
          |> Sanbase.Repo.preload(:product)
          |> Plan.maybe_create_plan_in_stripe()

        conn
        |> put_flash(:info, "Custom Plan created successfully.")
        |> redirect(to: Routes.custom_plan_path(conn, :show, custom_plan))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    custom_plan = Plan.by_id(id)

    custom_plan_users =
      Sanbase.Billing.Subscription.get_subscriptions_for_plan(id) |> Enum.map(& &1.user)

    render(conn, "show.html", custom_plan: custom_plan, custom_plan_users: custom_plan_users)
  end

  def edit(conn, %{"id" => id}) do
    custom_plan = Plan.by_id(id)
    changeset = Plan.changeset(custom_plan, %{})
    render(conn, "edit.html", custom_plan: custom_plan, changeset: changeset)
  end

  def update(conn, %{"id" => id, "plan" => params}) do
    custom_plan = Plan.by_id(id)
    args = params_to_args(params)

    case Plan.update_plan(custom_plan, args) do
      {:ok, custom_plan} ->
        conn
        |> put_flash(:info, "Custom Plan updated successfully.")
        |> redirect(to: Routes.custom_plan_path(conn, :show, custom_plan))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", custom_plan: custom_plan, changeset: changeset)
    end
  end

  defp params_to_args(params) do
    restrictions_params = params["restrictions"]

    realtime_data_cut_off_in_days =
      Map.fetch!(restrictions_params, "realtime_data_cut_off_in_days")

    historical_data_in_days = Map.fetch!(restrictions_params, "historical_data_in_days")

    restrictions = %{
      api_call_limits: Map.fetch!(restrictions_params, "api_call_limits") |> Jason.decode!(),
      query_access: Map.fetch!(restrictions_params, "query_access") |> Jason.decode!(),
      metric_access: Map.fetch!(restrictions_params, "metric_access") |> Jason.decode!(),
      signal_access: Map.fetch!(restrictions_params, "signal_access") |> Jason.decode!(),
      restricted_access_as_plan: Map.fetch!(restrictions_params, "restricted_access_as_plan"),
      realtime_data_cut_off_in_days:
        if(realtime_data_cut_off_in_days != "", do: realtime_data_cut_off_in_days),
      historical_data_in_days: if(historical_data_in_days != "", do: historical_data_in_days)
    }

    args = %{
      name: Map.fetch!(params, "name"),
      product_id: Sanbase.Billing.Product.product_api(),
      amount: Map.fetch!(params, "amount"),
      currency: Map.fetch!(params, "currency"),
      interval: Map.fetch!(params, "interval"),
      is_deprecated: false,
      is_private: true,
      order: 0,
      has_custom_restrictions: true,
      restrictions: restrictions
    }

    args
  end

  defimpl String.Chars, for: Map do
    def to_string(map) do
      inspect(map)
    end
  end
end
