defmodule Sanbase.Signals.Trigger.EthWalletTriggerSettings do
  @moduledoc ~s"""

  """

  use Vex.Struct

  import Sanbase.Math, only: [to_integer: 1]
  import Sanbase.Signals.Utils
  import Sanbase.Signals.Validation

  alias __MODULE__
  alias Sanbase.Signals.Type

  @derive {Jason.Encoder, except: [:_list, :payload, :triggered?]}
  @trigger_type "eth_wallet"

  @enforce_keys [:type, :channel, :trigger_time]
  defstruct type: @trigger_type,
            channel: nil,
            target: nil,
            filtered_target: %{list: []},
            threhsold: nil,
            payload: %{},
            triggered?: false

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  # Validations
  validates(:channel, &valid_notification_channel/1)
  validates(:target, &valid_eth_wallet_target?/1)
  validates(:threshold, &valid_threshold?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def get_data(%__MODULE__{filtered_target: %{list: target_list, type: :eth_address}} = settings) do
  end

  def get_data(%__MODULE__{filtered_target: %{list: target_list, type: :slug}} = settings) do
  end

  defp eth_balance_change(addresses) do
  end

  alias __MODULE__

  defimpl Sanbase.Signals.Settings, for: EthWalletTriggerSettings do
    def triggered?(%EthWalletTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%EthWalletTriggerSettings{target: target} = settings) do
    end

    def cache_key(%EthWalletTriggerSettings{} = settings) do
      construct_cache_key([settings.target, settings])
    end

    defp payload() do
    end
  end
end
