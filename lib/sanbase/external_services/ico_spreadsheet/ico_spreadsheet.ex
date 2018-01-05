defmodule Sanbase.ExternalServices.IcoSpreadsheet do
  use Tesla

  require Logger

  plug Tesla.Middleware.BaseUrl, "https://sheets.googleapis.com/v4/spreadsheets/"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  alias Sanbase.ExternalServices.IcoSpreadsheet.IcoSpreadsheetRow

  def get_project_data(document_id, api_key, project_names) when is_list(project_names) do
    Logger.info("Starting ICO spreadsheet fetch...")
    ico_spreasheet = ico_data_url(document_id, api_key)
    |> get()
    |> case do
      %{status: 200, body: %{"values" => data}} ->
        column_indices = hd(data) |> parse_header_row()

        tl(data)
        |> filter_value_rows(column_indices, project_names)
        |> parse_value_rows(column_indices)
    end
    Logger.info("Finished ICO spreadsheet fetch.")
    ico_spreasheet
  end

  defp ico_data_url(document_id, api_key) do
    "#{document_id}/values/ICOs?valueRenderOption=UNFORMATTED_VALUE&key=#{api_key}"
  end

  # TODO: get column indices from the header row
  defp parse_header_row(header_row) do
    IcoSpreadsheetRow.get_column_indices
  end

  defp filter_value_rows(value_rows, column_indices, project_names) do
    Enum.filter(value_rows, fn(value_row) ->
      project_name = get_value!(value_row, column_indices.project_name)

      !is_nil(project_name) and
        (Enum.empty?(project_names) or Enum.member?(project_names, project_name))
    end)
  end

  defp parse_value_rows(value_rows, column_indices) do
    value_rows
    |> Enum.map(&parse_value_row(&1, column_indices))
  end

  defp parse_value_row(value_row, column_indices) do
    project_name = get_value!(value_row, column_indices.project_name)

    res = column_indices
    |> Enum.map(&parse_value(value_row, &1, project_name))
    |> Enum.into(%{})
    |> handle_wallets()
    |> handle_infrastructure()
    |> handle_cap_currency()

    struct!(IcoSpreadsheetRow, res)
  end

  defp get_value!(value_row, column_index) do
    value = Enum.fetch(value_row, column_index)
    case value do
      {:ok, v} when v in ["", "n/a", "N/A", "-"] -> nil
      {:ok, v} -> v
      _ -> nil
    end
  end

  defp parse_value(value_row, {column, index}, project_name) do
    value = get_value!(value_row, index)
    value =
    case column do
      c when c in [:ico_start_date, :ico_end_date] ->
        parse_date(value, {project_name, column})
      c when c in [:tokens_issued_at_ico] ->
        parse_int(value, {project_name, column})
      c when c in [:tokens_sold_at_ico, :usd_btc_icoend, :funds_raised_btc, :funds_raised_usd, :funds_raised_eth, :usd_eth_icoend, :minimal_cap_amount, :maximal_cap_amount] ->
        parse_decimal(value, {project_name, column})
      c when c in [:ico_currencies] ->
        parse_comma_delimited(value, {project_name, column})
      _ -> parse_string(value, {project_name, column})
    end

    {column, value}
  end

  defp parse_int(value, {project_name, column}) when is_binary(value) do
    case Integer.parse(value) do
      {result, _} -> result
      _ -> #TODO: return error
        Logger.warn("[#{project_name}|#{column}] parse_int error: #{inspect value}")
        nil
    end
  end

  defp parse_int(value, _context), do: value

  defp parse_decimal(value, {project_name, column}) when is_binary(value) do
    case Decimal.parse(value) do
      {:ok, result} -> result
      _ -> #TODO: return error
        Logger.warn("[#{project_name}|#{column}] parse_decimal error: #{inspect value}")
        nil
    end
  end

  defp parse_decimal(value, _context), do: value

  defp parse_boolean(value, {project_name, column}) do
    value = if(is_binary(value)) do String.downcase(value) else value end

    case value do
      v when v in ["yes", "true", 1] -> true
      v when v in ["no", "false", 0] -> false
      nil -> nil
      _ -> #TODO: return error
        Logger.warn("[#{project_name}|#{column}] parse_boolean error: #{inspect value}")
        nil
    end
  end

  defp parse_date(value, _context) when is_integer(value) do
    #the -2 is to account for an Excel bug (search in internet)
    Date.add(~D[1900-01-01], value - 2)
  end

  defp parse_date(nil, _context), do: nil

  defp parse_date(value, {project_name, column}) do
    #TODO: return error
    Logger.warn("[#{project_name}|#{column}] parse_date error: #{inspect value}")
    nil
  end

  defp parse_comma_delimited(value, _context) when is_binary(value) do
    value
    |> String.split([",", ";"])
    |> Enum.map(&String.trim(&1))
    |> Enum.filter(&(String.length(&1) > 0))
  end

  defp parse_comma_delimited(nil, _context), do: []

  defp parse_comma_delimited(value, {project_name, column}) do
    #TODO: return error
    Logger.warn("[#{project_name}|#{column}] parse_comma_delimited error: #{inspect value}")
    []
  end

  defp parse_string(nil, _context), do: nil

  defp parse_string(value, _context) do
    to_string(value)
  end

  defp handle_wallets(parsed_value_row) do
    parsed_value_row
    |> Map.put(:eth_wallets, remove_nils([parsed_value_row.eth_wallet]))
    |> Map.put(:btc_wallets, remove_nils([parsed_value_row.btc_wallet, parsed_value_row.btc_wallet2, parsed_value_row.btc_wallet3, parsed_value_row.btc_wallet4, parsed_value_row.btc_wallet5]))
    |> Map.drop([:eth_wallet, :btc_wallet, :btc_wallet2, :btc_wallet3, :btc_wallet4, :btc_wallet5])
  end

  defp handle_infrastructure(parsed_value_row) do
    cond do
      is_nil(parsed_value_row.infrastructure) ->
        Map.put(parsed_value_row, :infrastructure, parsed_value_row.blockchain)
      true -> parsed_value_row
    end
    |> Map.drop([:blockchain])
  end

  defp handle_cap_currency(parsed_value_row) do
    value = if(!is_nil(parsed_value_row.cap_currency)) do String.downcase(parsed_value_row.cap_currency) else nil end

    case value do
      v when v in ["yes", "no"] ->
        Map.put(parsed_value_row, :cap_currency, nil)
      _ -> parsed_value_row
    end
  end

  defp remove_nils(list) when is_list(list) do
    Enum.reject(list, &is_nil/1)
  end
end
