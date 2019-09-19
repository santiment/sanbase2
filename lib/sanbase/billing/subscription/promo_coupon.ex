defmodule Sanbase.Billing.Subscription.PromoCoupon do
  @moduledoc """
  Module for persisting and sending coupons to customer's emails entered through our
  promotional sites.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.MandrillApi

  @email_template "Coupon for products"

  @promo_coupon_percent_off 25
  # FIXME end date of promotion ?
  @promo_end_datetime "2019-11-01T00:00:00Z"
  @promo_name "Promotional discount 25%"
  @promo_coupon_args %{
    name: @promo_name,
    percent_off: @promo_coupon_percent_off,
    duration: "once",
    max_redemptions: 1,
    redeem_by: Sanbase.DateTimeUtils.from_iso8601_to_unix!(@promo_end_datetime)
  }
  @promo_email_subject "Get #{@promo_coupon_percent_off}% off ANY Santiment product!"

  @type send_coupon_args :: %{email: String.t(), message: String.t() | nil}

  schema "promo_coupons" do
    field(:email, :string, null: false)
    field(:message, :string)
    field(:coupon, :string)
    field(:origin_url, :string)
  end

  def changeset(%__MODULE__{} = promo_coupon, attrs \\ %{}) do
    promo_coupon
    |> cast(attrs, [
      :email,
      :message,
      :coupon,
      :origin_url
    ])
    |> unique_constraint(:email)
  end

  @doc """
  Create a promotional coupon and send it to customer's specified email.
  If same email is entered more than once if resends the old coupon to this email.
  """
  @spec send_coupon(send_coupon_args) :: {:ok, any()} | {:error, any()}
  def send_coupon(%{email: email} = args) do
    with {:ok, promo_coupon} <- create_or_update(args),
         {:ok, coupon} <- get_or_create_coupon(promo_coupon) do
      send_coupon_email(email, coupon)
    end
  end

  def promo_coupon_args, do: @promo_coupon_args

  # helpers

  defp get_or_create_coupon(%__MODULE__{coupon: nil} = promo_coupon) do
    case StripeApi.create_promo_coupon(@promo_coupon_args) do
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
    MandrillApi.send(
      @email_template,
      email,
      %{
        "DISCOUNT" => percent_off,
        "COUPON_CODE" => id
      },
      %{
        subject: @promo_email_subject
      }
    )
  end
end
