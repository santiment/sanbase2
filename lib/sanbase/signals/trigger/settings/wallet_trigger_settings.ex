defmodule Sanbase.Signal.Trigger.WalletTriggerSettings do
  @moduledoc ~s"""
  The wallet signal is triggered when the balance of a wallet or set of wallets
  changes by a predefined amount for a specified asset (Ethereum, SAN tokens, Bitcoin, etc.)

  The signal can follow a single address, a list of addresses
  or a project. When a list of addresses or a project is followed, all the addresses
  are considered to be owned by a single entity and the transfers between them
  are excluded.
  """

  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.DateTimeUtils, only: [round_datetime: 2, str_to_sec: 1]

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Signal.Type

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "wallet_movement"

  @enforce_keys [:type, :channel, :target, :asset]
  defstruct type: @trigger_type,
            channel: nil,
            selector: nil,
            target: nil,
            operation: nil,
            time_window: "1d",
            filtered_target: %{list: []},
            payload: %{},
            triggered?: false

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          target: Type.complex_target(),
          selector: map(),
          operation: Type.operation(),
          time_window: Type.time_window(),
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  validates(:channel, &valid_notification_channel?/1)
  validates(:target, &valid_crypto_address?/1)
  validates(:selector, &valid_historical_balance_selector?/1)
  validates(:operation, &valid_operation?/1)
  validates(:time_window, &valid_time_window?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  def get_data(
        %__MODULE__{
          filtered_target: %{list: target_list, type: :address},
          selector: selector
        } = settings
      ) do
    {from, to} = get_timeseries_params(settings)

    target_list
    |> Enum.map(fn address ->
      with {:ok, [{address, {balance_before, balance_after, _balance_change}}]} <-
             balance_change(selector, address, from, to) do
        {address,
         [
           %{datetime: from, balance: balance_before},
           %{datetime: to, balance: balance_after}
         ]}
      end
    end)
    |> Enum.reject(&match?({:error, _}, &1))
  end

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  def get_data(
        %__MODULE__{
          filtered_target: %{list: target_list, type: :slug},
          selector: selector
        } = settings
      ) do
    {from, to} = get_timeseries_params(settings)

    target_list
    |> Project.by_slug()
    |> Enum.map(fn %Project{} = project ->
      {:ok, eth_addresses} = Project.eth_addresses(project)

      eth_addresses = Enum.map(eth_addresses, &String.downcase/1)

      with {:ok, data} <- balance_change(selector, eth_addresses, from, to) do
        {balance_before, balance_after} =
          data
          |> Enum.reduce(
            {0, 0},
            fn {_, {balance_before, balance_after, _change}},
               {balance_before_acc, balance_after_acc} ->
              {balance_before + balance_before_acc, balance_after + balance_after_acc}
            end
          )

        data = [
          %{datetime: from, balance: balance_before},
          %{datetime: to, balance: balance_after}
        ]

        {project.slug, data}
      end
    end)
    |> Enum.reject(&match?({:error, _}, &1))
  end

  defp get_timeseries_params(%{time_window: time_window}) do
    to = Timex.now()
    from = Timex.shift(to, seconds: -str_to_sec(time_window))

    {from, to}
  end

  defp balance_change(selector, address, from, to) do
    cache_key =
      {:wallet_signal, selector, address, round_datetime(from, 300), round_datetime(to, 300)}
      |> :erlang.phash2()

    Sanbase.Signal.Evaluator.Cache.get_or_store(cache_key, fn ->
      case Sanbase.Clickhouse.HistoricalBalance.balance_change(
             selector,
             address,
             from,
             to
           ) do
        {:ok, result} ->
          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  defimpl Sanbase.Signal.Settings, for: WalletTriggerSettings do
    import Sanbase.Signal.Utils

    alias Sanbase.Signal.{OperationText, ResultBuilder}

    def triggered?(%WalletTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%WalletTriggerSettings{} = settings, _trigger) do
      case WalletTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %WalletTriggerSettings{settings | triggered?: false}
      end
    end

    def build_result(data, %WalletTriggerSettings{} = settings) do
      ResultBuilder.build(data, settings, &payload/2, value_key: :balance)
    end

    def cache_key(%WalletTriggerSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.selector,
        settings.time_window,
        settings.operation
      ])
    end

    def payload(values, %{filtered_target: %{type: :address}} = settings) do
      """
      TODO address
      """
    end

    def payload(values, %{filtered_target: %{type: :slug}} = settings) do
      """
      TODO slug
      """
    end

    defp selector_to_name(%{infrastructure: "ETH"}), do: "1"
    defp selector_to_name(%{infrastructure: "BTC"}), do: "1"
    defp selector_to_name(%{infrastructure: "XRP"}), do: "1"
    defp selector_to_name(%{infrastructure: "BCH"}), do: "1"
    defp selector_to_name(%{infrastructure: "LTC"}), do: "1"
    defp selector_to_name(%{infrastructure: "EOS"}), do: "1"
  end
end
