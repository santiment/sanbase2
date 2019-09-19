defmodule Sanbase.Billing.Subscription.PromoCoupon do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.MandrillApi

  @template "Coupon for products"

  schema "promo_coupons" do
    field(:email, :string, null: false)
    field(:message, :string)
    field(:coupon, :string)
  end

  def changeset(%__MODULE__{} = promo_coupon, attrs \\ %{}) do
    promo_coupon
    |> cast(attrs, [
      :email,
      :message,
      :coupon
    ])
  end

  def send_coupon(%{email: email} = args) do
    with {:ok, promo_coupon} <- create_or_update(args),
         {:ok, coupon} <- get_or_create_coupon(promo_coupon) do
      send_coupon_email(email, coupon)
    end
  end

  defp get_or_create_coupon(%__MODULE__{coupon: nil} = promo_coupon) do
    case StripeApi.create_promo_coupon() do
      {:ok, coupon} ->
        do_update(promo_coupon, %{coupon: coupon.id})
        {:ok, coupon}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_or_create_coupon(%__MODULE__{coupon: coupon}) do
    StripeApi.retrieve_coupon(coupon)
  end

  defp create_or_update(%{email: email} = args) do
    email = String.downcase(email)

    case Repo.get_by(__MODULE__, email: email) do
      nil -> do_create(args)
      promo_coupon -> do_update(promo_coupon, args)
    end
  end

  defp do_create(args) do
    changeset(%__MODULE__{}, args)
    |> Repo.insert()
  end

  defp do_update(promo_coupon, args) do
    changeset(promo_coupon, args)
    |> Repo.update()
  end

  defp send_coupon_email(email, %Stripe.Coupon{id: id, percent_off: percent_off}) do
    MandrillApi.send(@template, email, %{
      "DISCOUNT" => percent_off,
      "COUPON_CODE" => id
    })
  end
end
