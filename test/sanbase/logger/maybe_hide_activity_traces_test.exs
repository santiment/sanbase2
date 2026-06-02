defmodule Sanbase.Logger.MaybeHideActivityTracesTest do
  # async: false — manipulates Logger.metadata; the application-installed
  # `:logger.primary_filter` is shared across the BEAM, so concurrent
  # tests changing :request_context could interfere with each other.
  use ExUnit.Case, async: false

  require Logger

  import ExUnit.CaptureLog

  alias Sanbase.Logger.MaybeHideActivityTraces, as: Filter
  alias Sanbase.RequestContext

  defp event(msg, meta), do: %{msg: msg, meta: meta, level: :info}

  defp protected_meta(extra \\ %{}) do
    Map.merge(
      %{
        request_context: %RequestContext{
          origin: :graphql,
          user_id: 1,
          activity_traces_hidden: true,
          auth_method: :apikey,
          product_code: "SANAPI"
        },
        request_id: "req-123"
      },
      extra
    )
  end

  defp safe_meta() do
    %{
      request_context: %RequestContext{
        origin: :graphql,
        user_id: 2,
        activity_traces_hidden: false
      }
    }
  end

  describe "filter/2" do
    test "rewrites ABSINTHE :string events to a redaction notice when protected" do
      ev = event({:string, "ABSINTHE schema=Sanbase op=Sensitive document=foo"}, protected_meta())

      assert %{msg: {:string, redacted}, meta: meta, level: :info} = Filter.filter(ev, [])

      assert redacted =~ "user_id=1"
      assert redacted =~ "activity_traces_hidden"
      refute redacted =~ "Sensitive"
      refute redacted =~ "document=foo"
      # RequestContext-derived hints are appended.
      assert redacted =~ "origin=graphql"
      assert redacted =~ "auth=apikey"
      assert redacted =~ "product=SANAPI"
      # Correlation-friendly meta survives.
      assert meta.request_id == "req-123"
      assert %RequestContext{} = meta.request_context
    end

    test "scrubs sensitive meta from non-ABSINTHE events when protected; keeps :complexity" do
      meta =
        protected_meta(%{
          remote_ip: "1.2.3.4",
          query: "currentUser",
          san_balance: 42,
          complexity: 100
        })

      ev = event({:string, "resolver failed: slug=bitcoin"}, meta)

      assert %{msg: {:string, "resolver failed: slug=bitcoin"}, meta: out_meta} =
               Filter.filter(ev, [])

      refute Map.has_key?(out_meta, :remote_ip)
      refute Map.has_key?(out_meta, :query)
      refute Map.has_key?(out_meta, :san_balance)
      assert out_meta.complexity == 100
      assert out_meta.request_id == "req-123"
      assert %RequestContext{} = out_meta.request_context
    end

    test "scrubs sensitive meta AND rewrites msg when ABSINTHE + protected" do
      meta = protected_meta(%{remote_ip: "1.2.3.4", query: "currentUser"})
      ev = event({:string, "ABSINTHE schema=foo op=Bar"}, meta)

      assert %{msg: {:string, redacted}, meta: out_meta} = Filter.filter(ev, [])

      assert redacted =~ "user_id=1"
      refute Map.has_key?(out_meta, :remote_ip)
      refute Map.has_key?(out_meta, :query)
    end

    # NOTE: `{format, args}` and `{:report, _}` msg shapes are intentionally
    # NOT rewritten — we only introspect `{:string, _}` (the shape Elixir
    # Logger lazy-fns and chardata-args land at after OTP normalization).
    # Other shapes are left as :other so the filter never has to invoke
    # `:io_lib.format/2` or call a `report_cb`, both of which can raise on
    # malformed input. Meta is still scrubbed in all cases.

    test "non-string msg shapes pass through unchanged (no rewrite, no raise)" do
      meta = protected_meta(%{remote_ip: "1.2.3.4"})

      for msg <- [
            {~c"~s schema=~s", [~c"ABSINTHE", ~c"Sanbase"]},
            {:report, %{report_cb: fn _ -> {~c"ABSINTHE", []} end}},
            {:report, %{label: :crash, report: %{}}},
            :unexpected_atom,
            42
          ] do
        assert %{msg: ^msg, meta: out_meta} = Filter.filter(event(msg, meta), [])
        refute Map.has_key?(out_meta, :remote_ip)
      end
    end

    test "rewrites Ecto QUERY logs to a SQL redaction notice when protected; appends ctx hints" do
      ev =
        event(
          {:string,
           "QUERY OK source=\"intraday_metrics\" db=2.3ms\nSELECT * FROM intraday_metrics WHERE slug='bitcoin'"},
          protected_meta()
        )

      assert %{msg: {:string, redacted}} = Filter.filter(ev, [])

      assert redacted =~ "user_id=1"
      assert redacted =~ "SQL"
      assert redacted =~ "activity_traces_hidden"
      assert redacted =~ "origin=graphql"
      assert redacted =~ "auth=apikey"
      refute redacted =~ "intraday_metrics"
      refute redacted =~ "bitcoin"
    end

    test "ctx hint includes :client for MCP origin" do
      meta = %{
        request_context: %RequestContext{
          origin: :mcp,
          user_id: 7,
          activity_traces_hidden: true,
          auth_method: :oauth,
          product_code: "SANAPI",
          client: "claude"
        }
      }

      ev = event({:string, "QUERY OK ... SELECT secret"}, meta)
      assert %{msg: {:string, redacted}} = Filter.filter(ev, [])

      assert redacted =~ "user_id=7"
      assert redacted =~ "origin=mcp"
      assert redacted =~ "auth=oauth"
      assert redacted =~ "client=claude"
      refute redacted =~ "SELECT secret"
    end

    test "ctx hint omits nil fields" do
      meta = %{
        request_context: %RequestContext{
          origin: :system,
          user_id: nil,
          activity_traces_hidden: true
        }
      }

      ev = event({:string, "QUERY OK ..."}, meta)
      assert %{msg: {:string, redacted}} = Filter.filter(ev, [])

      assert redacted =~ "origin=system"
      refute redacted =~ "auth="
      refute redacted =~ "product="
      refute redacted =~ "client="
    end

    test "rewrites Absinthe-style iodata (binary at head) when protected" do
      # Mimics what `Absinthe.Logger.log_run/2` actually emits after the
      # fn is evaluated: an iodata list whose head is the literal
      # "ABSINTHE" binary, followed by schema/variables/document.
      absinthe_iodata = [
        "ABSINTHE",
        " schema=",
        inspect(SanbaseWeb.Graphql.Schema),
        " variables=",
        inspect(%{}),
        ?\n,
        "---",
        ?\n,
        "{ hyperliquidBboPrices { timeseriesData(slug: \"bitcoin\") } }",
        ?\n,
        "---"
      ]

      ev = event({:string, absinthe_iodata}, protected_meta())

      assert %{msg: {:string, redacted}} = Filter.filter(ev, [])
      assert redacted =~ "user_id=1"
      assert redacted =~ "activity_traces_hidden"
      refute redacted =~ "hyperliquidBboPrices"
      refute redacted =~ "bitcoin"
    end

    test "rewrites Ecto QUERY ERROR logs too" do
      ev =
        event(
          {:string, "QUERY ERROR db=4.0ms\nSELECT bad FROM intraday_metrics WHERE slug='leak'"},
          protected_meta()
        )

      assert %{msg: {:string, redacted}} = Filter.filter(ev, [])
      refute redacted =~ "intraday_metrics"
      refute redacted =~ "leak"
    end

    test "leaves events alone when no request_context is set" do
      ev = event({:string, "ABSINTHE schema=foo"}, %{remote_ip: "1.2.3.4"})
      assert Filter.filter(ev, []) == :ignore
    end

    test "leaves events alone when request_context says not protected" do
      ev = event({:string, "ABSINTHE schema=foo"}, safe_meta())
      assert Filter.filter(ev, []) == :ignore
    end
  end

  describe "primary filter installed at application startup" do
    setup do
      # Ensure no leakage from other tests.
      Logger.reset_metadata([])
      on_exit(fn -> Logger.reset_metadata([]) end)

      # Remove any previously-registered version of the filter (stale
      # `&Filter.filter/2` reference pointing at an earlier compile) and
      # re-install the current one. `async: false` lets us mutate the
      # global primary-filter list safely.
      _ = :logger.remove_primary_filter(:sanbase_maybe_hide_activity_traces)

      :ok =
        :logger.add_primary_filter(
          :sanbase_maybe_hide_activity_traces,
          {&Filter.filter/2, []}
        )

      :ok
    end

    test "protected user: ABSINTHE log line is rewritten end-to-end" do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: 1,
          activity_traces_hidden: true
        }
      )

      log =
        capture_log(fn ->
          Logger.info("ABSINTHE schema=Sanbase op=Sensitive document=secret")
        end)

      # Original document content is gone…
      refute log =~ "Sensitive"
      refute log =~ "document=secret"
      # …but the redacted breadcrumb is present, with the user_id and reason.
      assert log =~ "user_id=1"
      assert log =~ "activity_traces_hidden"
    end

    test "non-protected user: ABSINTHE log line passes through" do
      Logger.metadata(
        request_context: %RequestContext{
          origin: :graphql,
          user_id: 2,
          activity_traces_hidden: false
        }
      )

      log =
        capture_log(fn ->
          Logger.info("ABSINTHE schema=Sanbase op=Public")
        end)

      assert log =~ "ABSINTHE"
      assert log =~ "Public"
    end

    test "no request_context: ABSINTHE log line passes through" do
      log = capture_log(fn -> Logger.info("ABSINTHE schema=Sanbase op=Anon") end)
      assert log =~ "ABSINTHE"
    end
  end
end
