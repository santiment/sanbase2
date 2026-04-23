defmodule SanbaseWeb.GenericAdmin.PromoTrial do
  @behaviour SanbaseWeb.GenericAdmin

  alias Sanbase.Billing.Subscription.PromoTrial

  def schema_module, do: PromoTrial
  def resource_name, do: "promo_trials"
  def singular_resource_name, do: "promo_trial"

  def resource do
    %{
      preloads: [:user],
      actions: [:new],
      new_fields: [:user, :trial_days, :plans],
      index_fields: [:id, :user_id, :plans, :trial_days, :created_at, :updated_at],
      belongs_to_fields: %{
        user: SanbaseWeb.GenericAdmin.belongs_to_user()
      },
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        plans: %{
          value_modifier: fn promo_trial ->
            id_name_map = PromoTrial.plan_id_name_map()

            promo_trial.plans
            |> Enum.map(fn plan -> id_name_map[plan] || plan end)
            |> Enum.join(",")
          end,
          collection: PromoTrial.plan_id_name_list(),
          type: :multiselect
        }
      }
    }
  end

  def after_filter(_promo_trial, _changeset, params) do
    PromoTrial.create_promo_trial(params)
  end
end
