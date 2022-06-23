defmodule Sanbase.Alert.Trigger.WalletUsdValuationTriggerSettings do
  @moduledoc ~s"""
  The wallet alert is triggered when the USD valuation of a wallet
  changes by a predefined amount, percent, etc.

  The alert can follow a single address, a list of addresses
  or a watchlist. When a watchlist is provided it is converted by the Trigger module
  to a list of addresses and that is all the alert sees.
  """
  @behaviour Sanbase.Alert.Trigger.Settings.Behaviour

  use Vex.Struct

  import Sanbase.{Validation, Alert.Validation}
  import Sanbase.DateTimeUtils, only: [round_datetime: 1, str_to_sec: 1]

  alias __MODULE__
  alias Sanbase.Alert.Type
  alias Sanbase.Clickhouse.HistoricalBalance

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "wallet_usd_valuation"

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
  validates(:selector, &valid_infrastructure_selector?/1)
  validates(:operation, &valid_operation?/1)
  validates(:time_window, &valid_time_window?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  def get_data(
        %__MODULE__{
          filtered_target: %{list: target_list},
          selector: selector
        } = settings
      ) do
    {from, to} = get_timeseries_params(settings)

    target_list
    |> Enum.map(fn address ->
      address = Sanbase.BlockchainAddress.to_internal_format(address)

      selector = %{
        address: address,
        infrastructure: selector.infrastructure
      }

      with {:ok, %{} = result} <- usd_value_change(selector, from, to) do
        {address,
         [
           %{datetime: from, usd_value: result.previous_usd_value},
           %{datetime: to, usd_value: result.current_usd_value}
         ]}
      else
        result ->
          raise("""
          The result returned from usd_value_change in WalletUsdValuationTriggerSettings has \
          different format than the expected one.
          Got: #{inspect(result)}
          """)
      end
    end)
    |> Enum.reject(&match?({:error, _}, &1))
    |> Enum.reject(&match?({:ok, []}, &1))
  end

  defp get_timeseries_params(%{time_window: time_window}) do
    to = Timex.now()
    from = Timex.shift(to, seconds: -str_to_sec(time_window))

    {from, to}
  end

  defp usd_value_change(selector, from, to) do
    cache_key =
      {__MODULE__, :usd_value_change, selector, round_datetime(from), round_datetime(to)}
      |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(:alerts_evaluator_cache, cache_key, fn ->
      # `to` is defined as Timex.now(). The function accepts only `from`
      # and automatically uses now() as `to`.

      {:ok, data} = HistoricalBalance.usd_value_address_change(selector, from)

      {previous_usd_value, current_usd_value} =
        Enum.reduce(data, {0, 0}, fn map, {prev, curr} ->
          {prev + map.previous_usd_value, curr + map.current_usd_value}
        end)

      {:ok,
       %{
         previous_usd_value: previous_usd_value,
         current_usd_value: current_usd_value
       }}
    end)
  end

  defimpl Sanbase.Alert.Settings, for: WalletUsdValuationTriggerSettings do
    import Sanbase.Alert.Utils

    alias Sanbase.Alert.{OperationText, ResultBuilder}

    def triggered?(%WalletUsdValuationTriggerSettings{triggered?: triggered}),
      do: triggered

    def evaluate(%WalletUsdValuationTriggerSettings{} = settings, _trigger) do
      case WalletUsdValuationTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %WalletUsdValuationTriggerSettings{settings | triggered?: false}
      end
    end

    def build_result(data, %WalletUsdValuationTriggerSettings{} = settings) do
      ResultBuilder.build(data, settings, &template_kv/2, value_key: :usd_value)
    end

    def cache_key(%WalletUsdValuationTriggerSettings{} = settings) do
      target =
        settings.target
        |> Map.replace(
          :address,
          Sanbase.BlockchainAddress.to_internal_format(settings.target.address)
        )

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

      kv =
        %{
          type: WalletUsdValuationTriggerSettings.type(),
          operation: settings.operation,
          address: settings.target.address
        }
        |> OperationText.merge_kvs(operation_kv)
        |> OperationText.merge_kvs(curr_value_kv)

      template = """
      The address {{address}}'s total USD valuation has #{operation_template}.
      #{curr_value_template}
      """

      {template, kv}
    end
  end
end
