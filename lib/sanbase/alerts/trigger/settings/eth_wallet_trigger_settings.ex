defmodule Sanbase.Alert.Trigger.EthWalletTriggerSettings do
  @moduledoc ~s"""
  The EthWallet alert is triggered when the balance of a wallet or set of wallets
  changes by a predefined amount for a specified asset (Ethereum, SAN tokens, etc.)

  The alert can follow a single ethereum address, a list of ethereum addresses
  or a project. When a list of addresses or a project is followed, all the addresses
  are considered to be owned by a single entity and the transfers between them
  are excluded.
  """
  @behaviour Sanbase.Alert.Trigger.Settings.Behaviour

  use Vex.Struct

  import Sanbase.Validation
  import Sanbase.Alert.Validation
  import Sanbase.Alert.OperationEvaluation
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1, round_datetime: 2]

  alias __MODULE__
  alias Sanbase.Alert.Type
  alias Sanbase.Project
  alias Sanbase.Clickhouse.HistoricalBalance

  @trigger_type "eth_wallet"
  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @enforce_keys [:type, :channel, :target, :asset]
  defstruct type: @trigger_type,
            channel: nil,
            target: nil,
            asset: nil,
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
          asset: Type.asset(),
          operation: Type.operation(),
          time_window: Type.time_window(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.tempalte_kv()
        }

  validates(:channel, &valid_notification_channel?/1)
  validates(:target, &valid_eth_wallet_target?/1)
  validates(:asset, &valid_slug?/1)
  validates(:operation, &valid_absolute_change_operation?/1)
  validates(:time_window, &valid_time_window?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  def get_data(
        %__MODULE__{
          filtered_target: %{list: target_list, type: :eth_address}
        } = settings
      ) do
    to = Timex.now()
    from = Timex.shift(to, seconds: -str_to_sec(settings.time_window))

    data =
      target_list
      |> Enum.map(fn addr ->
        case balance_change(addr, settings.asset.slug, from, to) do
          {:ok, [%{address: ^addr} = result]} ->
            {addr, from,
             %{
               balance_start: result.balance_start,
               balance_end: result.balance_end,
               balance_change: result.balance_change_amount
             }}

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, data}
  end

  def get_data(%__MODULE__{filtered_target: %{list: target_list, type: :slug}} = settings) do
    data =
      target_list
      |> Project.by_slug()
      |> Enum.map(fn %Project{} = project ->
        {_project, _from, _balances_map} =
          project_eth_addresses_balance(project, settings)
      end)

    {:ok, data}
  end

  defp project_eth_addresses_balance(project, settings) do
    to = Timex.now()
    from = Timex.shift(to, seconds: -str_to_sec(settings.time_window))
    {:ok, eth_addresses} = Project.eth_addresses(project)

    {:ok, project_balance_data} =
      eth_addresses
      |> Enum.map(&String.downcase/1)
      |> balance_change(settings.asset.slug, from, to)

    {balance_start, balance_end, balance_change} =
      aggregate_balance_changes(project_balance_data)

    {project, from,
     %{
       balance_start: balance_start,
       balance_end: balance_end,
       balance_change: balance_change
     }}
  end

  defp aggregate_balance_changes(balance_data) do
    {_balance_start, _balance_end, _balance_change} =
      balance_data
      |> Enum.reduce({0, 0, 0}, fn
        %{} = map, {start_acc, end_acc, change_acc} ->
          {
            start_acc + map.balance_start,
            end_acc + map.balance_end,
            change_acc + map.balance_change_amount
          }
      end)
  end

  defp balance_change(addresses, slug, from, to) do
    cache_key =
      {__MODULE__, :balance_change, addresses, slug, round_datetime(from, second: 60),
       round_datetime(to, second: 60)}
      |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(:alerts_evaluator_cache, cache_key, fn ->
      selector = %{infrastructure: "ETH", slug: slug}

      case HistoricalBalance.balance_change(selector, addresses, from, to) do
        {:ok, result} -> {:ok, result}
        _ -> {:ok, []}
      end
    end)
  end

  defimpl Sanbase.Alert.Settings, for: EthWalletTriggerSettings do
    def triggered?(%EthWalletTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%EthWalletTriggerSettings{} = settings, _trigger) do
      case EthWalletTriggerSettings.get_data(settings) do
        {:ok, list} when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          # TODO: Handle error case
          settings = %{settings | triggered?: false}
          {:ok, settings}
      end
    end

    # The result heavily depends on `last_triggered`, so just the settings are not enough
    def cache_key(%EthWalletTriggerSettings{}), do: :nocache

    defp build_result(list, settings) do
      template_kv =
        Enum.reduce(list, %{}, fn
          {project_or_addr, from, %{balance_change: balance_change} = balance_data}, acc ->
            case operation_triggered?(balance_change, settings.operation) do
              true ->
                Map.put(
                  acc,
                  to_identifier(project_or_addr),
                  template_kv(project_or_addr, settings, balance_data, from)
                )

              false ->
                acc
            end
        end)

      settings = %{settings | template_kv: template_kv, triggered?: template_kv != %{}}

      {:ok, settings}
    end

    defp to_identifier(%Project{slug: slug}), do: slug
    defp to_identifier(addr) when is_binary(addr), do: addr

    defp operation_text(%{amount_up: _}), do: "increased"
    defp operation_text(%{amount_down: _}), do: "decreased"

    defp template_kv(%Project{} = project, settings, balance_data, from) do
      kv = %{
        type: EthWalletTriggerSettings.type(),
        operation: settings.operation,
        project_name: project.name,
        project_slug: project.slug,
        asset: settings.asset.slug,
        since: DateTime.truncate(from, :second),
        balance_change_text: operation_text(settings.operation),
        balance_change: balance_data.balance_change,
        balance_change_abs: abs(balance_data.balance_change),
        balance: balance_data.balance_end,
        previous_balance: balance_data.balance_start
      }

      template = """
      🔔 \#{{project_ticker}} | **{{project_name}}**'s {{asset}} balance {{balance_change_text}} by {{balance_change}} since {{since}}.
      was: {{previous_balance}}, now: {{balance}}.
      """

      {template, kv}
    end

    defp template_kv(address, settings, balance_data, from) do
      asset = settings.asset.slug

      kv = %{
        type: EthWalletTriggerSettings.type(),
        operation: settings.operation,
        target: settings.target,
        asset: asset,
        address: address,
        historical_balance_link: SanbaseWeb.Endpoint.historical_balance_url(address, asset),
        since: DateTime.truncate(from, :second),
        balance_change: balance_data.balance_change,
        balance_change_abs: abs(balance_data.balance_change),
        balance: balance_data.balance_end,
        previous_balance: balance_data.balance_start
      }

      template = """
      🔔 The address {{address}}'s {{asset}} balance #{operation_text(settings.operation)} by {{balance_change_abs}} since {{since}}.
      was: {{previous_balance}}, now: {{balance}}
      """

      {template, kv}
    end
  end
end
