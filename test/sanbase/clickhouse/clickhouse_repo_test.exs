defmodule Sanbase.Clickhouse.ClickhouseRepoTest do
  use Sanbase.DataCase

  import ExUnit.CaptureLog
  alias Sanbase.ClickhouseRepo

  test "error handling when clickhouse repo returns error" do
    error_msg = "something went wrong with the connection"

    Sanbase.Mock.prepare_mock2(&ClickhouseRepo.query/2, {:error, error_msg})
    |> Sanbase.Mock.run_with_mocks(fn ->
      log =
        capture_log(fn ->
          {:error, error} = ClickhouseRepo.query_transform("SELECT NOW()", [], & &1)

          assert error =~
                   "Cannot execute ClickHouse database query. If issue persists please contact Santiment Support"

          # assert returned error message does not contain internal details
          refute error =~ error_msg

          # assert error starts with UUID
          assert <<"["::utf8, _uuid::binary-size(36), "]"::utf8, _message::binary>> = error
        end)

      # Only the log contains the internal error returned from CH
      assert log =~ error_msg
    end)
  end

  test "error handling when clickhouse throws exception" do
    error_msg = "something went wrong with the connection"

    Sanbase.Mock.prepare_mock(ClickhouseRepo, :query, fn _, _ -> raise(error_msg) end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      log =
        capture_log(fn ->
          {:error, error} = ClickhouseRepo.query_transform("SELECT NOW()", [], & &1)

          assert error =~
                   "Cannot execute ClickHouse database query. If issue persists please contact Santiment Support"

          # assert returned error message does not contain internal details
          refute error =~ error_msg

          # assert error starts with UUID
          assert <<"["::utf8, _uuid::binary-size(36), "]"::utf8, _message::binary>> = error
        end)

      # Only the log contains the internal error returned from CH
      assert log =~ error_msg

      # Log includes stacktrace as well
      assert log =~ "Stacktrace:"
    end)
  end
end
