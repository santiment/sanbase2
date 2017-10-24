defmodule Sanbase.ExternalServices.IcoSpreadsheet do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://sheets.googleapis.com/v4/spreadsheets/"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  # TODO: spreadsheet_id & api key should be fetched from env variables
  @spreadsheet_id "INSERT_SPREADSHEET_ID"
  @api_key "INSERT_API_KEY"

  def get_project_data!(project_names) when is_list(project_names) do
    ico_data_url()
    |> get()
    |> case do
      %{status: 200, body: %{"values" => data}} ->
        column_indices = hd(data) |> parse_header_row()

        tl(data)
        |> filter_value_rows(column_indices, project_names)
        |> parse_value_rows(column_indices)
    end
  end

  # TODO: get column indices from the header row
  # TODO: return all relevant columns
  defp parse_header_row(header_row) do
    %{
      project_name: 1,
      btc_marketcap: 3
    }
  end

  defp filter_value_rows(value_rows, column_indices, project_names) do
    Enum.filter(value_rows, fn(value_row) ->
      project_name = get_value!(value_row, column_indices.project_name)
      Enum.member?(project_names, project_name)
    end)
  end

  defp parse_value_rows(value_rows, column_indices) do
    value_rows
    |> Enum.map(&parse_value_row(&1, column_indices))
  end

  defp parse_value_row(value_row, column_indices) do
    column_indices
    |> Enum.map(&parse_value(value_row, &1))
    |> Enum.into(%{})
  end

  defp parse_value(value_row, {column, index}) do
    value = get_value!(value_row, index)
    # TODO: handle special cases
    case column do
      _ -> {column, value}
    end
  end

  defp get_value!(value_row, column_index) do
    Enum.fetch!(value_row, column_index)
  end

  defp ico_data_url do
    "#{@spreadsheet_id}/values/ICOs?key=#{@api_key}"
  end
end
