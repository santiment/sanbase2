defmodule Sanbase.Affiliate.FirstPromoterApi do
  @moduledoc """
  Wrapper for First Promoter promoters API: https://firstpromoter.com/api/v1/promoters/
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Utils.Config

  require Logger

  @promoters_api_base_url "https://firstpromoter.com/api/v1/promoters/"

  @type promoter_args :: %{
          optional(:ref_id) => String.t(),
          optional(:coupon_code) => String.t()
        }
  @type promoter :: map()

  @spec list() :: {:ok, list(promoter)} | {:error, String.t()}
  def list do
    do_list(promoters: [], page: 1)
  end

  @spec create(%User{}, promoter_args) :: {:ok, promoter} | {:error, String.t()}
  def create(user, args \\ %{})

  def create(%User{id: id, email: email}, args) when is_binary(email) do
    data = %{email: email, cust_id: id} |> Map.merge(args) |> URI.encode_query()

    @promoters_api_base_url
    |> Path.join("create")
    |> http_client().post(
      data,
      headers() ++ [{"Content-Type", "application/x-www-form-urlencoded"}]
    )
    |> handle_response()
  end

  def create(_user, _), do: {:error, "Can't create promoter account. User doesn't have an email address."}

  @spec show(String.t()) :: {:ok, promoter} | {:error, String.t()}
  def show(user_id) do
    @promoters_api_base_url
    |> Path.join("show?cust_id=#{user_id}")
    |> http_client().get(headers())
    |> handle_response()
  end

  @spec update(String.t(), promoter_args) :: {:ok, promoter} | {:error, String.t()}
  def update(user_id, args) do
    data = %{cust_id: user_id} |> Map.merge(args) |> URI.encode_query()

    @promoters_api_base_url
    |> Path.join("update")
    |> http_client().put(
      data,
      [{"Content-Type", "application/x-www-form-urlencoded"} | headers()]
    )
    |> handle_response()
  end

  @spec delete(String.t()) :: {:ok, promoter} | {:error, String.t()}
  def delete(user_id) do
    @promoters_api_base_url
    |> Path.join("delete?cust_id=#{user_id}")
    |> http_client().delete(headers())
    |> handle_response()
  end

  # helpers
  defp do_list(promoters: promoters, page: page) do
    @promoters_api_base_url
    |> Path.join("list?page=#{page}")
    |> http_client().get(headers())
    |> handle_response()
    |> case do
      {:ok, []} ->
        promoters

      {:ok, new_promoters} ->
        do_list(promoters: promoters ++ new_promoters, page: page + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response(response) do
    default_error_msg = "Error response from first promoter API"

    case response do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: _code, body: body}} = response ->
        Logger.error("#{default_error_msg}: #{inspect(filter_response(response))}")
        {:error, body |> Jason.decode!() |> Map.get("error", default_error_msg)}

      response ->
        Logger.error("#{default_error_msg}: #{inspect(filter_response(response))}")
        {:error, default_error_msg}
    end
  end

  defp http_client, do: HTTPoison

  defp headers do
    [
      {"x-api-key", "#{Config.module_get(__MODULE__, :api_key)}"}
    ]
  end

  defp filter_response({:ok, %HTTPoison.Response{request: %HTTPoison.Request{headers: _}} = response}) do
    Map.put(response, :request, Map.put(Map.from_struct(response.request), :headers, "***filtered***"))
  end

  defp filter_response(other), do: other
end
