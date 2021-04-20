defmodule Sanbase.WalletHunters.Vote do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.WalletHunters.{RelayerApi, RelayQuota}
  alias Sanbase.WalletHunters.Contract

  @retries_num 100
  @sleep_time 5000

  schema "wallet_hunters_votes" do
    field(:proposal_id, :integer)
    field(:transaction_id, :string)
    field(:transaction_status, :string, default: "pending")

    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(votes, attrs) do
    votes
    |> cast(attrs, [:user_id, :proposal_id, :transaction_id, :transaction_status])
    |> validate_required([:user_id, :proposal_id, :transaction_id, :transaction_status])
  end

  def poll_pending_transactions() do
    from(p in __MODULE__, where: p.transaction_status == "pending")
    |> Repo.all()
    |> Enum.each(fn %{transaction_id: transaction_id} ->
      poll_transaction_and_maybe_update(transaction_id)
    end)
  end

  def vote(%{request: request, signature: signature} = args) do
    with true <- RelayQuota.can_relay?(args.user_id, %{type: :vote}),
         {:ok, %{"hash" => transaction_id}} <- RelayerApi.relay(request, signature),
         {:ok, _} <- RelayQuota.create_or_update(args.user_id, %{type: :vote}),
         {:ok, proposal} <- create_db_vote(Map.put(args, :transaction_id, transaction_id)) do
      async_poll_transaction(transaction_id)
      {:ok, proposal}
    end
  end

  def vote(%{transaction_id: transaction_id} = args) do
    with {:ok, vote} <- create_db_vote(args) do
      async_poll_transaction(transaction_id)
      {:ok, vote}
    end
  end

  defp create_db_vote(args) do
    changeset(%__MODULE__{}, args)
    |> Repo.insert()
    |> case do
      {:ok, db_vote} -> {:ok, Repo.preload(db_vote, :user)}
      error -> error
    end
  end

  def fetch_by_transaction_id(transaction_id) do
    Repo.get_by(__MODULE__, transaction_id: transaction_id)
  end

  defp async_poll_transaction(transaction_id) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      check_transaction_status(transaction_id, 0)
    end)
  end

  defp check_transaction_status(_, @retries_num), do: :ok

  defp check_transaction_status(transaction_id, retries_so_far) do
    poll_transaction_and_maybe_update(transaction_id)
    |> case do
      {:ok, %__MODULE__{} = proposal} ->
        {:ok, proposal}

      error ->
        Process.sleep(@sleep_time)
        check_transaction_status(transaction_id, retries_so_far + 1)
    end
  end

  defp poll_transaction_and_maybe_update(transaction_id) do
    with {:ok, %{"blockNumber" => block_number}} when block_number != nil <-
           Contract.get_trx_by_id(transaction_id),
         {:ok, %{"logs" => logs} = receipt} when is_list(logs) <-
           Contract.get_trx_receipt_by_id(transaction_id) do
      if receipt["status"] == "0x1" do
        update_by_transaction_id(transaction_id, %{transaction_status: "ok"})
      else
        update_by_transaction_id(transaction_id, %{transaction_status: "error"})
      end
    end
  end

  defp update_by_transaction_id(transaction_id, params) do
    fetch_by_transaction_id(transaction_id)
    |> changeset(params)
    |> Repo.update()
  end
end
