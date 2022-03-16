defmodule Sanbase.Alert.Trigger.WalletAssetsHeldTriggerSettings do
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

  import Sanbase.{Validation, Alert.Validation}
  import Sanbase.DateTimeUtils, only: [round_datetime: 1, str_to_sec: 1]

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Alert.Type
  alias Sanbase.Clickhouse.HistoricalBalance

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "wallet_assets_held"

  @enforce_keys [:type, :channel, :target]
  defstruct type: @trigger_type,
            channel: nil,
            selector: nil,
            target: nil,
            operation: nil,
            time_window: "1d",
            # State keeps the list of assets that the address has held
            # during the last check. On every run the newly generated
            # list of assets is compared against the one stored in the
            # state. If there is a difference, the alert is triggered.
            state: %{},
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

  def post_create_process(trigger), do: fill_current_state(trigger)
  def post_update_process(trigger), do: fill_current_state(trigger)

  defp fill_current_state(trigger) do
    %{settings: settings} = trigger
    address_key_to_assets_list = get_data(settings)
    settings = %{settings | state: %{assets_held: address_key_to_assets_list}}

    %{trigger | settings: settings}
  end

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  def get_data(
        %__MODULE__{
          filtered_target: %{list: target_list},
          selector: selector
        } = settings
      ) do
    target_list
    |> Enum.map(fn address ->
      address = Sanbase.BlockchainAddress.to_internal_format(address)

      selector = %{
        address: address,
        infrastructure: selector.infrastructure
      }

      with {:ok, %{} = result} <- assets_held(selector) do
        {address, []}
      else
        result ->
          raise("""
          The result returned from assets_held in WalletAssetsHeldTriggerSettings has \
          different format than the expected one.
          Got: #{inspect(result)}
          """)
      end
    end)
    |> Enum.reject(&match?({:error, _}, &1))
    |> Enum.reject(&match?({:ok, []}, &1))
  end

  defp assets_held(selector) do
    cache_key =
      {__MODULE__, :assets_held, selector, round_datetime(DateTime.utc_now())}
      |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(:alerts_evaluator_cache, cache_key, fn ->
      before = Timex.shift(Timex.now(), day: -1)
      {:ok, data} = HistoricalBalance.usd_value_held_by_address(selector)
    end)
  end

  defimpl Sanbase.Alert.Settings, for: WalletAssetsHeldTriggerSettings do
    import Sanbase.Alert.Utils

    alias Sanbase.Alert.{OperationText, ResultBuilder}

    def triggered?(%WalletAssetsHeldTriggerSettings{triggered?: triggered}),
      do: triggered

    def evaluate(%WalletAssetsHeldTriggerSettings{} = settings, _trigger) do
      case WalletAssetsHeldTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %WalletAssetsHeldTriggerSettings{settings | triggered?: false}
      end
    end

    def build_result(data, %WalletAssetsHeldTriggerSettings{} = settings) do
      ResultBuilder.build(data, settings, &template_kv/2, value_key: :usd_value)
    end

    def cache_key(%WalletAssetsHeldTriggerSettings{} = settings) do
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
          type: WalletAssetsHeldTriggerSettings.type(),
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
