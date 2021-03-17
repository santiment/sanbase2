defmodule Sanbase.EventBus do
  @moduledoc """
  The eve
  """

  use EventBus.EventSource

  def notify(params) do
    params =
      params
      |> Map.merge(%{
        id: Map.get(params, :id, Ecto.UUID.generate()),
        topic: Map.fetch!(params, :topic),
        transaction_id: Map.get(params, :transaction_id),
        error_topic: Map.fetch!(params, :topic)
      })

    EventSource.notify params do
      data = Map.fetch!(params, :data)

      case Sanbase.EventBus.Event.valid?(data) do
        true -> data |> Map.delete(:extra_data)
        false -> raise("Invalid event submitted: #{inspect(params)}")
      end
    end
  end
end
