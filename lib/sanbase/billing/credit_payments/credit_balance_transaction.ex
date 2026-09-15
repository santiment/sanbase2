defmodule Sanbase.Billing.CreditPayments.CreditBalanceTransaction do
  @moduledoc ~s"""
  One entry of a customer's Stripe balance ledger, mirrored locally.

  `amount` keeps Stripe's own sign: negative credits the customer and is money that
  reached us, positive debits it - most often because an invoice drew on the balance.
  Readers that show money in flip the sign; nothing else does.

  The `description` is the internal note typed into Stripe when the credit was added,
  and is the only record of how a crypto or wire payment arrived.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "stripe_credit_balance_transactions" do
    field(:stripe_transaction_id, :string)
    field(:stripe_customer_id, :string)
    field(:granted_at, :utc_datetime)
    field(:amount, :integer, default: 0)
    field(:type, :string)
    field(:description, :string)
    field(:stripe_invoice_id, :string)
    field(:source, :string)
    field(:synced_at, :utc_datetime)

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @fields ~w(stripe_transaction_id stripe_customer_id granted_at amount type description
             stripe_invoice_id source synced_at user_id)a

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @fields)
    |> validate_required([:stripe_transaction_id, :stripe_customer_id, :granted_at, :synced_at])
    |> unique_constraint(:stripe_transaction_id)
  end
end
