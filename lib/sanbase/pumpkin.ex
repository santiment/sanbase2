defmodule Sanbase.Pumpkin do
  use Ecto.Schema
  import Ecto.Changeset

  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Accounts.Users
  alias Sanbase.Repo
  alias Sanbase.Billing.Product

  @percent_off 54
  @pumpkins_count 3

  schema "pumpkins" do
    field(:collected, :integer, default: 0)
    field(:coupon, :string)
    field(:pages, {:array, :string}, default: [])

    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(pumpkin, attrs) do
    pumpkin
    |> cast(attrs, [:collected, :coupon, :user_id, :pages])
    |> validate_required([:user_id])
  end

  def by_user(user_id) do
    Repo.get_by(__MODULE__, user_id: user_id)
  end

  def get_pumpkins(user_id) do
    by_user(user_id)
    |> case do
      %__MODULE__{collected: collected, pages: pages} -> {:ok, pages}
      nil -> {:ok, []}
    end
  end

  def update_pumpkins(user_id, page) do
    by_user(user_id)
    |> case do
      %__MODULE__{pages: pages} = pumpkin ->
        if page not in pages do
          pages = Enum.uniq(pages ++ [page])
          do_update(pumpkin, %{collected: length(pages), pages: pages})
        end

      nil ->
        do_create(%__MODULE__{}, %{user_id: user_id, collected: 1, pages: [page]})
    end
  end

  def do_create(pumpkin, params) do
    pumpkin
    |> changeset(params)
    |> Repo.insert()
  end

  def do_update(pumpkin, params) do
    pumpkin
    |> changeset(params)
    |> Repo.update()
  end

  def create_pumpkin_code(user_id) do
    with %__MODULE__{} = pumpkin <- by_user(user_id),
         :ok <- can_create_coupon(pumpkin),
         {:ok, %{"id" => coupon}} <- create_stripe_coupon_v2() do
      do_update(pumpkin, %{coupon: coupon})
      {:ok, coupon}
    else
      {:error, :eexist, coupon} -> {:ok, coupon}
      {:error, :enocollected, msg} -> {:error, msg}
      {:error, _} -> {:error, "Could not create coupon."}
      _ -> {:error, "Could not create coupon. Not all pumpkins collected"}
    end
  end

  def get_pumpkin_code(user_id) do
    by_user(user_id)
    |> case do
      nil -> {:ok, nil}
      %__MODULE__{coupon: coupon} -> {:ok, coupon}
    end
  end

  def can_create_coupon(%__MODULE__{collected: collected, coupon: coupon}) do
    cond do
      collected < 3 ->
        {:error, :enocollected, "Could not create coupon. Not all pumpkins collected"}

      not is_nil(coupon) ->
        {:error, :eexist, coupon}

      true ->
        :ok
    end
  end

  def create_stripe_coupon() do
    # needs applies_to - so it is only to Sanbase product
    Stripe.Coupon.create(%{
      percent_off: @percent_off,
      duration: "once",
      redeem_by: DateTime.to_unix(~U[2022-11-05 23:59:59.999999Z]),
      name: "Halloween Sanbase Discount"
    })
  end

  # Make a raw call skipping Stripity lib since it does not support `applies_to` param
  def create_stripe_coupon_v2 do
    %{
      "percent_off" => @percent_off,
      "duration" => "once",
      "redeem_by" => DateTime.to_unix(~U[2022-11-05 23:59:59.999999Z]),
      "name" => "Halloween Sanbase Discount",
      "max_redemptions" => 1,
      "applies_to[products][]" => Product.by_id(Product.product_sanbase()).stripe_id
    }
    |> do_create_coupon()
  end

  def do_create_coupon(payload) do
    HTTPoison.post(
      "https://api.stripe.com/v1/coupons",
      URI.encode_query(payload),
      headers()
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: status_code} = response}
      when status_code >= 200 and status_code < 300 ->
        {:ok, Jason.decode!(response.body)}

      {:ok, %HTTPoison.Response{} = response} ->
        {:error, response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp basic_auth do
    Base.encode64(Config.module_get!(Sanbase.StripeConfig, :api_key) <> ":" <> "")
  end

  defp headers do
    [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "application/json"},
      {"Authorization", "Basic #{basic_auth()}"}
    ]
  end
end
