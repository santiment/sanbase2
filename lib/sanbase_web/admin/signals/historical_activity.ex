defmodule Sanbase.ExAdmin.Signals.HistoricalActivity do
  use ExAdmin.Register

  register_resource Sanbase.Signals.HistoricalActivity do
    action_items(only: [:show])

    index do
      column(:user)
      column(:user_trigger_id)
      column(:triggered_at)
      column(:payload, &Jason.encode!(&1.payload))
    end

    show historical_activity do
      attributes_table do
        row(:user)
        row(:user_trigger_id)
        row(:triggered_at)
        row("Payload", &Jason.encode!(&1.payload))
      end
    end
  end
end
