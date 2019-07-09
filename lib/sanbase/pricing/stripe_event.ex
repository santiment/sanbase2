defmodule Sanbase.Pricing.StripeEvent do
  @moduledoc """
  Module for persisting Stripe webhook events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Pricing.Subscription
  alias Sanbase.StripeApi

  @primary_key false
  schema "stripe_events" do
    field(:event_id, :string, primary_key: true)
    field(:type, :string, null: false)
    field(:payload, :map, null: false)
    field(:is_processed, :boolean, default: false)
  end

  def changeset(%__MODULE__{} = stripe_event, attrs \\ %{}) do
    stripe_event
    |> cast(attrs, [:event_id, :type, :payload, :is_processed])
    |> validate_required([:event_id, :type, :payload, :is_processed])
  end

  def by_id(event_id) do
    Repo.get(__MODULE__, event_id)
  end

  def create(
        %{
          "id" => id,
          "type" => type
        } = stripe_event
      ) do
    %__MODULE__{}
    |> changeset(%{event_id: id, type: type, payload: Jason.encode!(stripe_event)})
    |> Repo.insert()
  end

  def update(id, params) do
    by_id(id)
    |> changeset(params)
    |> Repo.update()
  end

  def handle_event_async(stripe_event) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      handle_event(stripe_event)
    end)
  end

  defp handle_event(%{
         "id" => id,
         "type" => "invoice.payment_succeeded",
         "data" => %{"object" => %{"subscription" => subscription_id}}
       }) do
    {:ok, stripe_subscription} = StripeApi.retrieve_subscription(subscription_id)

    Subscription
    |> Repo.get_by(stripe_id: stripe_subscription.id)
    |> Subscription.update_subscription_db(%{
      current_period_end: stripe_subscription.current_period_end
    })

    update(id, %{is_processed: true})
  end
end
