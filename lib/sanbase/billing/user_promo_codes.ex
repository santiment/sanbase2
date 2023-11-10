defmodule Sanbase.Billing.UserPromoCode do
  use Ecto.Schema

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan

  import Ecto.Query
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime]
  schema "user_promo_codes" do
    field(:campaign, :string)
    field(:coupon, :string)
    field(:percent_off, :integer)
    field(:redeem_by, :utc_datetime)
    field(:max_redemptions, :integer, default: 1)
    field(:times_redeemed, :integer, default: 0)
    field(:metadata, :map, default: %{})
    field(:extra_data, :map, default: %{})

    field(:valid, :boolean, default: true)

    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = promo, attrs) do
    promo
    |> cast(attrs, [
      :campaign,
      :coupon,
      :user_id,
      :percent_off,
      :redeem_by,
      :metadata,
      :extra_data,
      :max_redemptions,
      :times_redeemed
    ])
    |> validate_required([:campaign, :coupon, :user_id, :redeem_by, :percent_off])
  end

  def create(args) do
    changeset(%__MODULE__{}, args)
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Mark that the coupon has been used one time by increasing
  the times_redeemed field by one. This is done so we can stop
  showing used codes in the list of the available user promo codes
  """
  def use_coupon(coupon) do
    from(p in __MODULE__, where: p.coupon == ^coupon)
    |> Repo.update_all(inc: [times_redeemed: +1])
  end

  @doc ~s"""
  Get all currently valid promo codes for a user
  """
  def get_user_promo_codes(user_id) do
    user_promo_codes_base_query(user_id)
    |> Repo.all()
  end

  @doc ~s"""
  Get all promo codes for a campgain, including no longer valid promo codes.
  This is used when counting how many promo codes in total have been issued
  """
  def get_total_user_promo_codes_for_campaign(user_id, campaign) do
    query = from(p in __MODULE__, where: p.user_id == ^user_id and p.campaign == ^campaign)

    {:ok, Repo.all(query)}
  end

  def is_coupon_usable(nil, _), do: true

  def is_coupon_usable(coupon, %Plan{} = plan) do
    case Repo.get_by(__MODULE__, coupon: coupon) do
      nil ->
        # If there is no information in this table, this means that the coupon
        # is issued in another way, e.g. by Stripe directly. In this case, we
        # cannot check if the coupon is usable, so we assume it is. If it is not
        # the step that submits it to the Stripe API will fail
        true

      %__MODULE__{} = promo ->
        product = get_in(promo, [:metadata, "product"])

        cond do
          not is_nil(product) and product != plan.product.code ->
            {:error, "The coupon is not valid for this product."}

          # The rest of the checks are not really needed as Stripe API will
          # check them anyway, but we do them here to avoid unnecessary API
          # calls and to have more unified coupon validation failed messages
          DateTime.compare(DateTime.utc_now(), coupon.redeem_by) == :gt ->
            {:error, "The coupon has expired."}

          promo.times_redeemed >= promo.max_redemptions ->
            {:error, "The coupon has been used too many times."}

          true ->
            true
        end
    end
  end

  # Private functions
  defp user_promo_codes_base_query(user_id) do
    from(p in __MODULE__,
      where:
        p.user_id == ^user_id and
          p.max_redemptions > p.times_redeemed and
          p.redeem_by > fragment("now()") and p.valid == true
    )
  end
end
