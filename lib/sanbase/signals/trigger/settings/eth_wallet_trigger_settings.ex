defmodule Sanbase.Signals.Trigger.EthWalletTriggerSettings do
  @moduledoc ~s"""

  """

  use Vex.Struct

  import Sanbase.Signals.Validation

  alias __MODULE__
  alias Sanbase.Signals.{Type, Trigger}
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance
  alias Sanbase.Signals.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "eth_wallet"

  @enforce_keys [:type, :channel, :target, :asset]
  defstruct type: @trigger_type,
            channel: nil,
            target: nil,
            asset: nil,
            filtered_target: %{list: []},
            threshold: nil,
            payload: %{},
            triggered?: false,
            created_at: DateTime.utc_now()

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          target: Type.complex_target(),
          asset: Type.asset(),
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          created_at: DateTime.t()
        }

  validates(:channel, &valid_notification_channel/1)
  validates(:target, &valid_eth_wallet_target?/1)
  validates(:asset, &valid_slug?/1)
  validates(:threshold, &valid_threshold?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def get_data(
        %__MODULE__{filtered_target: %{list: target_list, type: :eth_address}} = settings,
        trigger
      ) do
    now = Timex.now()

    target_list
    |> Enum.map(fn addr ->
      from = Trigger.last_triggered(trigger, addr) || settings.created_at
      address_balance_change = balance_change(addr, settings.asset.slug, from, now)
      {:eth_address, addr, address_balance_change}
    end)
  end

  def get_data(
        %__MODULE__{filtered_target: %{list: target_list, type: :slug}} = settings,
        trigger
      ) do
    now = Timex.now()

    target_list
    |> Project.by_slug()
    |> Enum.map(fn %Project{eth_addresses: eth_addresses, coinmarketcap_id: slug} = project ->
      from = Trigger.last_triggered(trigger, slug) || settings.created_at

      project_balance_change =
        eth_addresses
        |> Enum.reduce(0, fn %{address: addr}, balance ->
          balance + balance_change(addr, settings.asset.slug, from, now)
        end)

      {:project, project, project_balance_change}
    end)
  end

  defp balance_change(address, slug, from, to) do
    from_rounded = div(DateTime.to_unix(from, :second), 300) * 300
    to_rounded = div(DateTime.to_unix(to, :second), 300) * 300

    Cache.get_or_store(
      "balance_change_#{address}_#{slug}_#{from_rounded}_#{to_rounded}",
      fn ->
        HistoricalBalance.balance_change(address, slug, from, to)
        |> case do
          {:ok, {_, _, change}} -> change
          _ -> 0
        end
      end
    )
  end

  alias __MODULE__

  defimpl Sanbase.Signals.Settings, for: EthWalletTriggerSettings do
    def triggered?(%EthWalletTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%EthWalletTriggerSettings{} = settings, trigger) do
      case EthWalletTriggerSettings.get_data(settings, trigger) do
        list when is_list(list) and list != [] ->
          build_result(list, settings, trigger)

        _ ->
          %EthWalletTriggerSettings{
            settings
            | triggered?: false
          }
      end
    end

    # The result heavily depends on `last_triggered`, so just the settings are not enough
    def cache_key(%EthWalletTriggerSettings{}), do: :nocache

    defp build_result(list, settings, trigger) do
      threshold = settings.threshold

      payload =
        Enum.reduce(list, %{}, fn
          {:project, project, balance_change}, payload when abs(balance_change) >= threshold ->
            Map.put(
              payload,
              project.coinmarketcap_id,
              payload(project, settings, balance_change, trigger)
            )

          {:eth_address, address, balance_change}, payload when balance_change >= threshold ->
            Map.put(payload, address, payload(address, settings, balance_change, trigger))

          _, payload ->
            payload
        end)

      %EthWalletTriggerSettings{
        settings
        | payload: payload,
          triggered?: payload != %{}
      }
    end

    defp payload(
           %Project{name: name, coinmarketcap_id: slug} = project,
           settings,
           balance_change,
           trigger
         ) do
      """
      The #{settings.asset.slug} balance of #{name} wallets has changed by #{balance_change} since #{
        Trigger.last_triggered(trigger, slug) || settings.created_at
      }

      More info here: #{Sanbase.Model.Project.sanbase_link(project)}
      """
    end

    defp payload(address, settings, balance_change, trigger) do
      """
      The #{settings.asset.slug} balance of the address #{address} has changed by #{
        balance_change
      } since #{Trigger.last_triggered(trigger, address) || settings.created_at}
      """
    end
  end
end
