defmodule Sanbase.Pricing.StripeEvent do
  @moduledoc """
  Module for persisting Stripe webhook events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Pricing.Subscription
  alias Sanbase.StripeApi

  require Logger

  @primary_key false
  schema "stripe_events" do
    field(:event_id, :string, primary_key: true)
    field(:type, :string, null: false)
    field(:payload, :map, null: false)
    field(:is_processed, :boolean, default: false)

    timestamps()
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
    |> changeset(%{event_id: id, type: type, payload: stripe_event})
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
    with {:ok, stripe_subscription} <- StripeApi.retrieve_subscription(subscription_id),
         {:nil?, subscription} <-
           {:nil?, Repo.get_by(Subscription, stripe_id: stripe_subscription.id)},
         {:ok, _subscription} <-
           Subscription.update_subscription_db(subscription, %{
             current_period_end: DateTime.from_unix!(stripe_subscription.current_period_end)
           }) do
      update(id, %{is_processed: true})
    else
      {:nil?, _} ->
        error_msg = "Subscription with stripe_id: #{subscription_id} does not exist"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, reason} ->
        Logger.error("Error handling invoice.payment_succeeded event: reason #{inspect(reason)}")
        {:error, reason}
    end
  end
end
