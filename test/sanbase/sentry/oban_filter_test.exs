defmodule Sanbase.Sentry.ObanFilterTest do
  use ExUnit.Case, async: true

  alias Sanbase.Sentry.ObanFilter

  doctest Sanbase.Sentry.ObanFilter

  test "query refresh failures are reported only on the final attempt" do
    for attempt <- 1..2 do
      job = %Oban.Job{attempt: attempt, max_attempts: 3}
      refute ObanFilter.report?(Sanbase.Queries.RefreshWorker, job)
    end

    assert ObanFilter.report?(Sanbase.Queries.RefreshWorker, %Oban.Job{
             attempt: 3,
             max_attempts: 3
           })
  end

  test "other workers report every failed attempt" do
    job = %Oban.Job{attempt: 1, max_attempts: 20}

    assert ObanFilter.report?(Sanbase.Accounts.User.UniswapStaking, job)
    assert ObanFilter.report?(nil, job)
  end
end
