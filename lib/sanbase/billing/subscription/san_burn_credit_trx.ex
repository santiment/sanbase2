defmodule Sanbase.Billing.Subscription.SanBurnCreditTransaction do
  use Ecto.Schema

  require Logger

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @san_contract "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
  @san_burn_address "0x000000000000000000000000000000000000dead"
  @san_burn_coeff 2
  @pending_stale_seconds 300
  @retry_max_age_seconds 7 * 86_400
  @statuses ~w(pending credited failed)

  schema "san_burn_credit_transactions" do
    field(:address, :string)
    field(:trx_hash, :string)
    field(:san_amount, :float)
    field(:san_price, :float)
    field(:credit_amount, :float)
    field(:trx_datetime, :utc_datetime)
    field(:status, :string, default: "credited")
    field(:stripe_credit_id, :string)

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
      :status,
      :stripe_credit_id,
      :user_id
    ])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:trx_hash)
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def exist?(trx_hash) do
    from(t in __MODULE__,
      where: t.trx_hash == ^trx_hash and t.status == "credited"
    )
    |> Repo.exists?()
  end

  def all() do
    Repo.all(__MODULE__)
  end

  def run() do
    {:ok, burn_trxs} = fetch_burn_trxs()

    (burn_trxs ++ fetch_retryable_trxs())
    |> Enum.uniq_by(& &1.trx_hash)
    |> do_run()
  end

  def do_run(burn_trxs) do
    burn_trxs
    |> Enum.each(fn burn_trx ->
      if not exist?(burn_trx.trx_hash) do
        try do
          save(burn_trx)
        catch
          kind, reason ->
            Logger.error(
              "Save burn transaction #{burn_trx.trx_hash} failed (#{kind}): #{Exception.format_banner(kind, reason)}"
            )
        end
      end
    end)
  end

  def fetch_burn_trxs() do
    query_struct = fetch_san_burns_query()

    ClickhouseRepo.query_transform(query_struct, fn [timestamp, address, value, trx_id] ->
      %{
        trx_datetime: DateTime.from_unix!(timestamp),
        address: address,
        san_amount: value,
        trx_hash: trx_id
      }
    end)
  end

  @doc ~s"""
  Failed and stale pending claims whose burn happened in the last 7 days.
  `fetch_burn_trxs/0` only covers the last day, so these are retried from the
  stored rows. Older claims are left for manual review.
  """
  def fetch_retryable_trxs() do
    oldest =
      DateTime.utc_now()
      |> DateTime.add(-@retry_max_age_seconds, :second)
      |> DateTime.truncate(:second)

    from(t in reclaimable_query(),
      where: t.trx_datetime > ^oldest,
      select: %{
        trx_datetime: t.trx_datetime,
        address: t.address,
        san_amount: t.san_amount,
        trx_hash: t.trx_hash
      }
    )
    |> Repo.all()
  end

  @doc ~s"""
  Credit the user that made the burn and record it. A pending row is committed
  first so the unique index on `trx_hash` claims the burn before any Stripe call.
  A Stripe credit whose description includes the full hash is recorded without
  adding a new credit.

  A retry of a failed or stale claim credits the user and amount stored on the
  claim. If the address now belongs to a different user, the claim is marked
  failed and nothing is credited, so the burn can be resolved manually.
  """
  def save(burn_trx) do
    san_price = fetch_san_pice(burn_trx.trx_datetime)
    credit_amount = round(burn_trx.san_amount * san_price * @san_burn_coeff)

    result =
      with {:ok, user} <- fetch_user_by_address(burn_trx.address),
           {:ok, record} <- claim_burn(user, credit_amount, san_price, burn_trx) do
        credit_and_finalize(record, user, burn_trx)
      end

    case result do
      {:ok, record} ->
        {:ok, record}

      {:error, :already_claimed} = error ->
        Logger.info("SAN burn transaction #{burn_trx.trx_hash} is already claimed, skipping")
        error

      {:error, :recipient_changed} = error ->
        error

      error ->
        Logger.error("Save burn transaction error: #{inspect(error)}")
        error
    end
  end

  defp claim_burn(user, credit_amount, san_price, burn_trx) do
    params =
      Map.merge(burn_trx, %{
        user_id: user.id,
        credit_amount: credit_amount,
        san_price: san_price,
        status: "pending"
      })

    case create(params) do
      {:ok, record} ->
        {:ok, record}

      {:error, %Ecto.Changeset{} = changeset} = error ->
        if unique_trx_hash_error?(changeset) do
          reclaim_burn(burn_trx.trx_hash, user)
        else
          error
        end
    end
  end

  # Only the stored recipient can reclaim. The stored `user_id`, `credit_amount`
  # and `san_price` are kept, so a retry sends Stripe the same request as the
  # first attempt and the idempotency key returns its credit.
  defp reclaim_burn(trx_hash, user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    reclaimable = from(t in reclaimable_query(), where: t.trx_hash == ^trx_hash)

    query = from(t in reclaimable, where: t.user_id == ^user.id, select: t)

    case Repo.update_all(query, set: [status: "pending", updated_at: now]) do
      {1, [record]} -> {:ok, record}
      {0, _} -> fail_if_recipient_changed(reclaimable, user, now)
    end
  end

  defp fail_if_recipient_changed(reclaimable, user, now) do
    query = from(t in reclaimable, select: t)

    case Repo.update_all(query, set: [status: "failed", updated_at: now]) do
      {0, _} ->
        {:error, :already_claimed}

      {1, [record]} ->
        Logger.error(
          "SAN burn transaction #{record.trx_hash} was claimed for user #{record.user_id}, " <>
            "but its address #{record.address} now belongs to user #{user.id}. " <>
            "Not crediting it, resolve it manually."
        )

        {:error, :recipient_changed}
    end
  end

  defp reclaimable_query() do
    stale_before =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-@pending_stale_seconds, :second)
      |> NaiveDateTime.truncate(:second)

    from(t in __MODULE__,
      where: t.status == "failed" or (t.status == "pending" and t.updated_at < ^stale_before)
    )
  end

  defp credit_and_finalize(record, user, burn_trx) do
    credit_amount = round(record.credit_amount)

    with {:ok, user} <- Sanbase.Billing.create_or_update_stripe_customer(user),
         {:ok, existing_credit} <-
           find_stripe_credit(user.stripe_customer_id, burn_trx.trx_hash),
         {:ok, stripe_credit} <-
           credit_unless_credited(existing_credit, user, credit_amount, burn_trx) do
      finalize_credited(record, stripe_credit, existing_credit)
    else
      {:error, _} = error ->
        mark_failed(record)
        error

      error ->
        mark_failed(record)
        {:error, error}
    end
  end

  defp credit_unless_credited(nil, user, credit_amount, burn_trx) do
    add_credit_to_stripe(user, credit_amount, burn_trx)
  end

  defp credit_unless_credited(existing_credit, _user, _credit_amount, burn_trx) do
    Logger.warning(
      "SAN burn transaction #{burn_trx.trx_hash} is already credited in Stripe " <>
        "(#{existing_credit.id}), recording it without adding a new credit"
    )

    {:ok, existing_credit}
  end

  defp finalize_credited(record, stripe_credit, existing_credit) do
    attrs =
      %{
        status: "credited",
        stripe_credit_id: Map.get(stripe_credit, :id)
      }
      |> maybe_put_existing_credit_amount(existing_credit)

    record
    |> change(attrs)
    |> Repo.update()
  end

  defp maybe_put_existing_credit_amount(attrs, nil), do: attrs

  defp maybe_put_existing_credit_amount(attrs, existing_credit) do
    Map.put(attrs, :credit_amount, -existing_credit.amount / 100)
  end

  defp mark_failed(record) do
    record
    |> change(status: "failed")
    |> Repo.update()
  end

  def find_stripe_credit(customer_id, trx_hash) when is_binary(trx_hash) and trx_hash != "" do
    hash = String.downcase(trx_hash)

    with {:ok, transactions} <-
           Sanbase.StripeApi.list_all_customer_balance_transactions(customer_id) do
      credit =
        Enum.find(transactions, fn trx ->
          trx.amount < 0 and is_binary(trx.description) and
            String.contains?(String.downcase(trx.description), hash)
        end)

      {:ok, credit}
    end
  end

  def find_stripe_credit(_customer_id, _trx_hash), do: {:ok, nil}

  defp unique_trx_hash_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:trx_hash, {_, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
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
