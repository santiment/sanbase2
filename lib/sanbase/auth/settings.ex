defmodule Sanbase.Auth.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:signal_notify_email, :boolean, default: false)
    field(:signal_notify_telegram, :boolean, default: false)
    field(:telegram_chat_id, :integer)
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [
      :signal_notify_email,
      :signal_notify_telegram,
      :telegram_chat_id
    ])
  end
end
