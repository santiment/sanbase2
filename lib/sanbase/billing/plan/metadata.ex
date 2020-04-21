defmodule Sanbase.Billing.Plan.Metadata do
  # Sanbase PRO $49/month
  def current_free_trial_plan, do: 201
  # Sanbase PRO $51/month and $49/month
  def free_trial_plans, do: [13, 201]
  def sandata_premium, do: 43
end
