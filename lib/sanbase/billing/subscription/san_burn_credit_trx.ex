defmodule Sanbase.Billing.Subscription.SanBurnCreditTrx do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Account.User
  alias Sanbase.Repo

  @san_contract "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
  @san_burn_address "0x000000000000000000000000000000000000dead"
  @san_burn_coeff 2

  schema "san_burn_credit_trx" do
    field(:address, :string)
    field(:trx_hash, :string)
    field(:san_amount, :float)
    field(:san_price, :float)
    field(:credit_amount, :float)
    field(:trx_datetime, :utc_datetime)

    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = burn_trx, attrs \\ %{}) do
    burn_trx
    |> cast(attrs, [
      :address,
      :trx_hash,
      :san_amount,
      :san_price,
      :credit_amount,
      :trx_datetime,
      :user_id
    ])
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def all do
    Repo.all(__MODULE__)
  end

  def run do
    {:ok, burn_trxs} = fetch_burn_trxs()

    burn_trxs
    |> Enum.each(fn burn_trx ->
      save(burn_trx)
    end)
  end

  def fetch_burn_trxs do
    {query, args} = fetch_san_burns_query()

    ClickhouseRepo.query_transform(query, args, fn [dt, address, value, trx_id] ->
      %{
        trx_datetime: dt,
        address: address,
        san_amount: value,
        trx_hash: trx_id
      }
    end)
  end

  def save(burn_trx) do
    san_price = fetch_san_pice(burn_trx.trx_datetime)

    credit_amount = burn_trx.san_amount * san_price * @san_burn_coeff

    {:ok, user} = fetch_user_by_address(burn_trx.address)

    add_credit_to_stripe(user, credit_amount, burn_trx)

    params =
      %{
        user_id: user.id,
        credit_amount: credit_amount,
        san_price: san_price
      }
      |> Map.merge(burn_trx)

    create(params)
  end

  def fetch_san_pice(datetime) do
    {:ok, price} = Sanbase.Price.last_record_before("santiment", datetime)
    price.price_usd
  end

  def fetch_user_by_address(address) do
    user_id = EthAccount.by_address(address).user_id
    Sanbase.Accounts.get_user(user_id)
  end

  def add_credit_to_stripe(user, amount, burn_trx) do
    {:ok, user} = Sanbase.Billing.create_or_update_stripe_customer(user)

    Sanbase.StripeApi.add_credit(user.stripe_customer_id, amount, burn_trx.trx_hash)
  end

  def fetch_san_burns_query() do
    query = """
    SELECT dt, from, value / pow(10, 18), transactionHash
    FROM erc20_transfers_to
    WHERE dt > now() - INTERVAL 100 DAY and contract = ?1 and to = ?2
    """

    {query, [@san_contract, @san_burn_address]}
  end
end
