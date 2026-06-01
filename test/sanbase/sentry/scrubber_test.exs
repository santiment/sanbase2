defmodule Sanbase.Sentry.ScrubberTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts
  alias Sanbase.Sentry.Scrubber
  alias Sentry.Event
  alias Sentry.Interfaces.{Breadcrumb, Exception, Request, Stacktrace}

  setup do
    protected = insert(:user)
    unprotected = insert(:user)
    Sanbase.PrivacyCacheSeed.seed!([protected.id])
    {:ok, protected: protected, unprotected: unprotected}
  end

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

  test "protected user: query/variables in request.data are replaced with masked sentinel", %{
    protected: user
  } do
    masked = Accounts.masked_sentinel()

    event =
      event_with(user.id,
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

  test "protected user: ABSINTHE breadcrumbs are dropped, others remain", %{protected: user} do
    crumbs = [
      %Breadcrumb{message: "ABSINTHE schema=foo", category: "absinthe"},
      %Breadcrumb{message: "kept", category: "other"}
    ]

    event = event_with(user.id, breadcrumbs: crumbs)
    %Event{breadcrumbs: result} = Scrubber.before_send(event)

    assert [%Breadcrumb{message: "kept"}] = result
  end

  test "non-protected user: event passes through unchanged", %{unprotected: user} do
    crumbs = [%Breadcrumb{message: "ABSINTHE schema=foo"}]
    event = event_with(user.id, breadcrumbs: crumbs)

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

  test "atom-keyed data map is scrubbed too", %{protected: user} do
    masked = Accounts.masked_sentinel()
    event = event_with(user.id, data: %{query: "q", variables: %{}})
    %Event{request: %Request{data: data}} = Scrubber.before_send(event)
    assert data.query == masked
    assert data.variables == masked
  end

  test "protected user: exception value and stack-frame locals are masked", %{protected: user} do
    masked = Accounts.masked_sentinel()

    event =
      %{
        event_with(user.id, [])
        | exception: [
            %Exception{
              type: "RuntimeError",
              value: "no metric named price_for_protected_slug_bitcoin",
              stacktrace: %Stacktrace{
                frames: [
                  %Stacktrace.Frame{
                    function: "Sanbase.Metric.fetch/2",
                    filename: "lib/metric.ex",
                    vars: %{slug: "bitcoin", metric: "price_usd"}
                  }
                ]
              }
            }
          ]
      }

    %Event{exception: [scrubbed]} = Scrubber.before_send(event)

    assert scrubbed.value == masked
    assert [%Stacktrace.Frame{vars: nil}] = scrubbed.stacktrace.frames
  end

  test "protected user: event.extra is wholesale masked", %{protected: user} do
    masked = Accounts.masked_sentinel()
    event = %{event_with(user.id, []) | extra: %{"slug" => "bitcoin", "metric" => "price_usd"}}
    %Event{extra: extra} = Scrubber.before_send(event)
    assert extra == %{"slug" => masked, "metric" => masked}
  end

  test "non-protected user: exception and extra are left untouched", %{unprotected: user} do
    event =
      %{
        event_with(user.id, [])
        | exception: [%Exception{type: "RuntimeError", value: "boom"}],
          extra: %{"slug" => "bitcoin"}
      }

    out = Scrubber.before_send(event)
    assert out.exception == event.exception
    assert out.extra == event.extra
  end

  test "config wires Sanbase.Sentry.Scrubber.before_send/1 as the Sentry callback" do
    # If this assertion ever fails, masking is silently disabled — even if
    # all the unit tests above still pass.
    assert {Sanbase.Sentry.Scrubber, :before_send} ==
             Application.fetch_env!(:sentry, :before_send)
  end
end
