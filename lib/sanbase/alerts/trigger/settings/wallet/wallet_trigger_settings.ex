defmodule Sanbase.Alert.Trigger.WalletTriggerSettings do
  @moduledoc ~s"""
  The wallet alert is triggered when the balance of a wallet or set of wallets
  changes by a predefined amount for a specified asset (Ethereum, SAN tokens, Bitcoin, etc.)

  The alert can follow a single address, a list of addresses
  or a project. When a list of addresses or a project is followed, all the addresses
  are considered to be owned by a single entity and the transfers between them
  are excluded.
  """
  @behaviour Sanbase.Alert.Trigger.Settings.Behaviour

  use Vex.Struct

  import Sanbase.Alert.Validation
  import Sanbase.DateTimeUtils, only: [round_datetime: 1, str_to_sec: 1]
  import Sanbase.Validation

  alias __MODULE__
  alias Sanbase.Alert.Type
  alias Sanbase.Project

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "wallet_movement"

  @enforce_keys [:type, :channel, :target]
  defstruct type: @trigger_type,
            channel: nil,
            selector: nil,
            target: nil,
            operation: nil,
            time_window: "1d",
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          target: Type.complex_target(),
          selector: map(),
          operation: Type.operation(),
          time_window: Type.time_window(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  validates(:channel, &valid_notification_channel?/1)
  validates(:target, &valid_crypto_address?/1)
  validates(:target, &valid_combine_balances_flag?/1)
  validates(:selector, &valid_historical_balance_selector?/1)
  validates(:operation, &valid_operation?/1)
  validates(:time_window, &valid_time_window?/1)

  @spec type() :: String.t()
  def type, do: @trigger_type

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  def get_data(%__MODULE__{filtered_target: %{list: target_list, type: :address}, selector: selector} = settings) do
    {from, to} = get_timeseries_params(settings)

    target_list
    |> Enum.map(fn address ->
      address = Sanbase.BlockchainAddress.to_internal_format(address)

      selector = %{
        address: address,
        infrastructure: selector.infrastructure
      }

      case balance_change(selector, address, from, to) do
        {:ok, [%{address: ^address} = result]} ->
          {address,
           [
             %{datetime: from, balance: result.balance_start},
             %{datetime: to, balance: result.balance_end}
           ]}

        {:ok, [%{address: returned_address}]} ->
          raise("""
          The address returned from balance_change in WalletTriggerSettings has
          different format than the provided address or it returned a completely
          different address.
          Got: #{inspect(returned_address)}, Expected: #{inspect(address)}
          """)

        _ ->
          {:ok, []}
      end
    end)
    |> Enum.reject(&(match?({:error, _}, &1) or match?({:ok, []}, &1)))
    |> maybe_combine_balances(settings)
  end

  def get_data(%__MODULE__{filtered_target: %{list: target_list, type: :slug}, selector: selector} = settings) do
    {from, to} = get_timeseries_params(settings)

    target_list
    |> Project.by_slug()
    |> Enum.map(fn %Project{} = project ->
      {:ok, eth_addresses} = Project.eth_addresses(project)

      eth_addresses = Enum.map(eth_addresses, &String.downcase/1)

      with {:ok, data} <- balance_change(selector, eth_addresses, from, to) do
        {balance_before, balance_after} =
          Enum.reduce(
            data,
            {0, 0},
            fn %{} = result, {balance_before_acc, balance_after_acc} ->
              {result.balance_start + balance_before_acc, result.balance_end + balance_after_acc}
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
    |> maybe_combine_balances(settings)
  end

  defp get_timeseries_params(%{time_window: time_window}) do
    to = DateTime.utc_now()
    from = Timex.shift(to, seconds: -str_to_sec(time_window))

    {from, to}
  end

  defp balance_change(selector, address, from, to) do
    cache_key =
      Sanbase.Cache.hash({__MODULE__, :wallet_signal, selector, address, round_datetime(from), round_datetime(to)})

    Sanbase.Cache.get_or_store(:alerts_evaluator_cache, cache_key, fn ->
      Sanbase.Clickhouse.HistoricalBalance.balance_change(selector, address, from, to)
    end)
  end

  defimpl Sanbase.Alert.Settings, for: WalletTriggerSettings do
    import Sanbase.Alert.Utils

    alias Sanbase.Alert.OperationText
    alias Sanbase.Alert.ResultBuilder

    def triggered?(%WalletTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%WalletTriggerSettings{} = settings, _trigger) do
      case WalletTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          settings = %WalletTriggerSettings{settings | triggered?: false}
          {:ok, settings}
      end
    end

    def build_result(data, %WalletTriggerSettings{} = settings) do
      ResultBuilder.build(data, settings, &template_kv/2, value_key: :balance)
    end

    def cache_key(%WalletTriggerSettings{} = settings) do
      to_internal = fn target, field ->
        case Map.get(target, field) do
          nil -> nil
          [_ | _] = list -> Enum.map(list, &Sanbase.BlockchainAddress.to_internal_format/1)
          <<_::binary>> = value -> Sanbase.BlockchainAddress.to_internal_format(value)
        end
      end

      target =
        settings.target
        |> Map.replace(:address, to_internal.(settings.target, :address))
        |> Map.replace(:eth_address, to_internal.(settings.target, :eth_address))

      construct_cache_key([
        settings.type,
        target,
        settings.selector,
        settings.time_window,
        settings.operation
      ])
    end

    defp template_kv(values, %{filtered_target: %{type: :address}} = settings) do
      {operation_template, operation_kv} =
        OperationText.to_template_kv(values, settings.operation)

      {curr_value_template, curr_value_kv} = OperationText.current_value(values)

      asset_target_blockchain_kv = asset_target_blockchain_kv(settings.selector)

      kv =
        %{
          type: WalletTriggerSettings.type(),
          operation: settings.operation,
          address: values.identifier
        }
        |> OperationText.merge_kvs(operation_kv)
        |> OperationText.merge_kvs(curr_value_kv)
        |> OperationText.merge_kvs(asset_target_blockchain_kv)

      template = """
      The address {{address}}'s {{asset}} balance on the {{target_blockchain}} blockchain has #{operation_template}.
      #{curr_value_template}
      """

      {template, kv}
    end

    defp template_kv(%{identifier: slug} = values, %{filtered_target: %{type: :slug}} = settings) do
      project = Project.by_slug(slug)

      {operation_template, operation_kv} =
        OperationText.to_template_kv(values, settings.operation)

      {curr_value_template, curr_value_kv} = OperationText.current_value(values)

      asset_target_blockchain_kv = asset_target_blockchain_kv(settings.selector)

      kv =
        %{
          type: WalletTriggerSettings.type(),
          project_name: project.name,
          project_ticker: project.ticker,
          project_slug: project.slug,
          operation: settings.operation
        }
        |> OperationText.merge_kvs(operation_kv)
        |> OperationText.merge_kvs(curr_value_kv)
        |> OperationText.merge_kvs(asset_target_blockchain_kv)

      template = """
      🔔 \#{{project_ticker}} | **{{project_name}}**'s {{asset}} balance on the {{target_blockchain}} blockchain has #{operation_template}.
      #{curr_value_template}
      """

      {template, kv}
    end

    defp asset_target_blockchain_kv(%{infrastructure: infrastructure} = selector) do
      case infrastructure do
        "ETH" -> %{asset: Map.get(selector, :slug, "ethereum"), target_blockchain: "Ethereum"}
        "BNB" -> %{asset: Map.get(selector, :slug, "binance-coin"), target_blockchain: "Binance"}
        "XRP" -> %{asset: Map.get(selector, :currency, "XRP"), target_blockchain: "XRP Ledger"}
        "BTC" -> %{asset: "bitcoin", target_blockchain: "Bitcoin"}
        "BCH" -> %{asset: "bitcoin-cash", target_blockchain: "Bitcoin Cash"}
        "LTC" -> %{asset: "litecoin", target_blockchain: "Litecoin"}
      end
    end
  end

  defp maybe_combine_balances([], _settings), do: []

  defp maybe_combine_balances(data, settings) do
    if Map.get(settings.target, :use_combined_balance, false) do
      [{_addr, first_balance} | rest] =
        data

      combined_balance =
        Enum.reduce(rest, first_balance, fn {_addr, balances}, acc ->
          [%{datetime: from, balance: balance_start}, %{datetime: to, balance: balance_end}] =
            acc

          [%{balance: addr_balance_start}, %{balance: addr_balance_end}] = balances

          [
            %{datetime: from, balance: balance_start + addr_balance_start},
            %{datetime: to, balance: balance_end + addr_balance_end}
          ]
        end)

      combined_addresses = Enum.map_join(data, ", ", &elem(&1, 0))
      combined_addresses = "(combined balances of) " <> combined_addresses
      [{combined_addresses, combined_balance}]
    else
      data
    end
  end
end
