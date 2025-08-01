defmodule Sanbase.Billing.Subscription.SanBurnCreditTransaction do
  use Ecto.Schema

  require Logger

  import Ecto.Changeset

  alias Sanbase.ChRepo
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @san_contract "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
  @san_burn_address "0x000000000000000000000000000000000000dead"
  @san_burn_coeff 2

  schema "san_burn_credit_transactions" do
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

  def exist?(trx_hash) do
    not is_nil(Repo.get_by(__MODULE__, trx_hash: trx_hash))
  end

  def all() do
    Repo.all(__MODULE__)
  end

  def run() do
    {:ok, burn_trxs} = fetch_burn_trxs()

    do_run(burn_trxs)
  end

  def do_run(burn_trxs) do
    burn_trxs
    |> Enum.each(fn burn_trx ->
      if not exist?(burn_trx.trx_hash) do
        save(burn_trx)
      end
    end)
  end

  def fetch_burn_trxs do
    query_struct = fetch_san_burns_query()

    ChRepo.query_transform(query_struct, fn [timestamp, address, value, trx_id] ->
      %{
        trx_datetime: DateTime.from_unix!(timestamp),
        address: address,
        san_amount: value,
        trx_hash: trx_id
      }
    end)
  end

  def save(burn_trx) do
    san_price = fetch_san_pice(burn_trx.trx_datetime)
    credit_amount = round(burn_trx.san_amount * san_price * @san_burn_coeff)

    with {:ok, user} <- fetch_user_by_address(burn_trx.address),
         {:ok, _} <- add_credit_to_stripe(user, credit_amount, burn_trx) do
      params =
        %{
          user_id: user.id,
          credit_amount: credit_amount,
          san_price: san_price
        }
        |> Map.merge(burn_trx)

      create(params)
    else
      error -> Logger.error("Save burn transaction error: #{inspect(error)}")
    end
  end

  def fetch_san_pice(datetime) do
    {:ok, price} = Sanbase.Price.last_record_before("santiment", datetime)

    if price do
      price.price_usd
    else
      fetch_current_san_price()
    end
  end

  def fetch_current_san_price() do
    url =
      "https://api.coingecko.com/api/v3/simple/token_price/ethereum?contract_addresses=0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098&vs_currencies=usd"

    response = HTTPoison.get!(url)
    price = Jason.decode!(response.body)["0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"]["usd"]
    price
  end

  def fetch_user_by_address(address) do
    case EthAccount.by_address(address) do
      nil -> {:error, "No registered user with address: #{address}"}
      eth_account -> Sanbase.Accounts.get_user(eth_account.user_id)
    end
  end

  def add_credit_to_stripe(user, amount, burn_trx) do
    {:ok, user} = Sanbase.Billing.create_or_update_stripe_customer(user)

    # Negative amount means to credit user balance. Value is in cents
    Sanbase.StripeApi.add_credit(user.stripe_customer_id, -amount * 100, burn_trx.trx_hash)
  end

  defp fetch_san_burns_query() do
    sql = """
    SELECT toUnixTimestamp(dt), from, value / pow(10, 18), transactionHash
    FROM erc20_transfers
    WHERE
      dt > now() - INTERVAL 1 DAY AND
      contract = {{contract}} AND
      to = {{to}}
    """

    params = %{contract: @san_contract, to: @san_burn_address}

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
