defmodule Sanbase.Sentry.ObanTagsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Sentry.ObanTags

  test "promotes the known entity ids to tags" do
    job = %{args: %{"query_id" => 667, "user_id" => 3207, "next_refresh_in_seconds" => 86_400}}

    assert ObanTags.from_job(job) == %{oban_query_id: "667", oban_user_id: "3207"}
  end

  test "ignores the args that are not in the allowlist" do
    job = %{args: %{"slug" => "bitcoin"}}

    assert ObanTags.from_job(job) == %{}
  end

  test "handles jobs without args" do
    assert ObanTags.from_job(%{}) == %{}
    assert ObanTags.from_job(%{args: nil}) == %{}
  end

  test "put_job_context/1 stores the tags in the Sentry context" do
    job = %{args: %{"query_id" => 667, "user_id" => 3207}}

    assert :ok = ObanTags.put_job_context(job)

    assert %{tags: %{oban_query_id: "667", oban_user_id: "3207"}} = Sentry.Context.get_all()
  end
end
