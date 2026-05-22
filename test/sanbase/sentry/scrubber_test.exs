defmodule Sanbase.Sentry.ScrubberTest do
  use ExUnit.Case, async: true

  alias Sanbase.Accounts
  alias Sanbase.Sentry.Scrubber
  alias Sentry.Event
  alias Sentry.Interfaces.{Breadcrumb, Request}

  defp event_with(user_id, opts) do
    data = Keyword.get(opts, :data, %{"query" => "{ viewer { id } }", "variables" => %{}})
    breadcrumbs = Keyword.get(opts, :breadcrumbs, [])

    %Event{
      event_id: "00000000000000000000000000000000",
      timestamp: "2026-01-01T00:00:00Z",
      user: %{id: user_id},
      request: %Request{method: "POST", url: "/graphql", data: data},
      breadcrumbs: breadcrumbs
    }
  end

  defp protected_id, do: Accounts.activity_traces_hidden_user_ids() |> Enum.at(0)

  defp unprotected_id do
    Enum.find(10_000..20_000, fn id ->
      not MapSet.member?(Accounts.activity_traces_hidden_user_ids(), id)
    end)
  end

  test "protected user: query/variables in request.data are replaced with masked sentinel" do
    masked = Accounts.masked_sentinel()

    event =
      event_with(protected_id(),
        data: %{
          "query" => "query Sensitive { viewer { id } }",
          "variables" => %{"slug" => "bitcoin"},
          "operationName" => "Sensitive"
        }
      )

    %Event{request: %Request{data: data}} = Scrubber.before_send(event)

    assert data["query"] == masked
    assert data["variables"] == masked
    assert data["operationName"] == masked
  end

  test "protected user: ABSINTHE breadcrumbs are dropped, others remain" do
    crumbs = [
      %Breadcrumb{message: "ABSINTHE schema=foo", category: "absinthe"},
      %Breadcrumb{message: "kept", category: "other"}
    ]

    event = event_with(protected_id(), breadcrumbs: crumbs)
    %Event{breadcrumbs: result} = Scrubber.before_send(event)

    assert [%Breadcrumb{message: "kept"}] = result
  end

  test "non-protected user: event passes through unchanged" do
    crumbs = [%Breadcrumb{message: "ABSINTHE schema=foo"}]
    event = event_with(unprotected_id(), breadcrumbs: crumbs)

    assert Scrubber.before_send(event) == event
  end

  test "no user.id: event passes through unchanged" do
    event = %Event{
      event_id: "00000000000000000000000000000000",
      timestamp: "2026-01-01T00:00:00Z",
      user: %{},
      request: %Request{data: %{"query" => "q", "variables" => %{}}},
      breadcrumbs: []
    }

    assert Scrubber.before_send(event) == event
  end

  test "atom-keyed data map is scrubbed too" do
    masked = Accounts.masked_sentinel()
    event = event_with(protected_id(), data: %{query: "q", variables: %{}})
    %Event{request: %Request{data: data}} = Scrubber.before_send(event)
    assert data.query == masked
    assert data.variables == masked
  end
end
