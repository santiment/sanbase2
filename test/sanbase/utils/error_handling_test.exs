defmodule Sanbase.Utils.ErrorHandlingTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Sanbase.Utils.ErrorHandling

  describe "internal_error_message/2" do
    test "returns only the public message and a log id, and logs the details" do
      error = %Postgrex.Error{message: "relation \"secret_table\" does not exist"}

      log =
        capture_log(fn ->
          message = ErrorHandling.internal_error_message("Failed to fetch insights", error)

          assert message =~
                   ~r/^\[[0-9a-f-]{36}\] Failed to fetch insights\. See logs for details\.$/

          refute message =~ "secret_table"
          send(self(), {:message, message})
        end)

      assert_received {:message, message}
      [_, log_id] = Regex.run(~r/^\[([0-9a-f-]{36})\]/, message)
      assert log =~ log_id
      assert log =~ "secret_table"
    end
  end
end
