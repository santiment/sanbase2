defmodule Sanbase.Signal.Trigger.EthWalletTriggerSettings do
  @moduledoc ~s"""
  The EthWallet signal is triggered when the balance of a wallet or set of wallets
  changes by a predefined amount for a specified asset (Ethereum, SAN tokens, etc.)

  The signal can follow a single ethereum address, a list of ethereum addresses
  or a project. When a list of addresses or a project is followed, all the addresses
  are considered to be owned by a single entity and the transfers between them
  are excluded.
  """

  use Vex.Struct

  import Sanbase.Validation
  import Sanbase.Signal.Validation
  import Sanbase.Signal.OperationEvaluation
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1, round_datetime: 2]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance
  alias Sanbase.Signal.Evaluator.Cache

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

    target_list
    |> Enum.map(fn addr ->
      case balance_change(addr, settings.asset.slug, from, to) do
        [{^addr, {start_balance, end_balance, balance_change}}] ->
          {addr, from,
           %{
             start_balance: start_balance,
             end_balance: end_balance,
             balance_change: balance_change
           }}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def get_data(%__MODULE__{filtered_target: %{list: target_list, type: :slug}} = settings) do
    to = Timex.now()
    from = Timex.shift(to, seconds: -str_to_sec(settings.time_window))

    target_list
    |> Project.by_slug()
    |> Enum.map(fn %Project{} = project ->
      {:ok, eth_addresses} = Project.eth_addresses(project)

      project_balance_data =
        eth_addresses
        |> Enum.map(&String.downcase/1)
        |> balance_change(settings.asset.slug, from, to)
        |> Enum.map(fn {_, data} -> data end)

      {start_balance, end_balance, balance_change} =
        project_balance_data
        |> Enum.reduce({0, 0, 0}, fn
          {start_balance, end_balance, balance_change}, {start_acc, end_acc, change_acc} ->
            {
              start_acc + start_balance,
              end_acc + end_balance,
              change_acc + balance_change
            }
        end)

      {project, from,
       %{
         start_balance: start_balance,
         end_balance: end_balance,
         balance_change: balance_change
       }}
    end)
  end

  defp balance_change(addresses, slug, from, to) do
    cache_key =
      {:balance_change, addresses, slug, round_datetime(from, 300), round_datetime(to, 300)}
      |> Sanbase.Cache.hash()

    Cache.get_or_store(
      cache_key,
      fn ->
        selector = %{infrastructure: "ETH", slug: slug}

        HistoricalBalance.balance_change(selector, addresses, from, to)
        |> case do
          {:ok, result} -> result
          _ -> []
        end
      end
    )
  end

  alias __MODULE__

  defimpl Sanbase.Signal.Settings, for: EthWalletTriggerSettings do
    def triggered?(%EthWalletTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%EthWalletTriggerSettings{} = settings, _trigger) do
      case EthWalletTriggerSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %EthWalletTriggerSettings{settings | triggered?: false}
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

      %EthWalletTriggerSettings{
        settings
        | template_kv: template_kv,
          triggered?: template_kv != %{}
      }
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
        balance: balance_data.end_balance,
        previous_balance: balance_data.start_balance
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
        balance: balance_data.end_balance,
        previous_balance: balance_data.start_balance
      }

      template = """
      🔔The address {{address}}'s {{asset}} balance #{operation_text(settings.operation)} by {{balance_change_abs}} since {{since}}.
      was: {{previous_balance}, now: {{balance}}
      """

      {template, kv}
    end
  end
end
