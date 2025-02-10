defmodule Sanbase.Cryptocompare.HistoricalDataStub do
  @moduledoc false
  def ohlcv_price_data(base_asset, quote_asset, date) do
    date =
      case date do
        str when is_binary(str) -> Date.from_iso8601!(str)
        date -> date
      end

    body = """
    time,fromsymbol,tosymbol,open,high,low,close,volume_from,volume_to
    #{plus_minute_unix(date, 0)},#{base_asset},#{quote_asset},6241.908080470284,6267.326355454034,6240.674651886244,6250.308944432027,248.36219959,1553761.3212507297
    #{plus_minute_unix(date, 1)},#{base_asset},#{quote_asset},6250.308944432027,6250.252094881613,6242.063392647832,6242.400315239814,66.46741731999998,414508.7590691053
    #{plus_minute_unix(date, 2)},#{base_asset},#{quote_asset},6242.400315239814,6242.094267553671,6197.939996238564,6197.939996238564,402.73847456,2496888.8341799136
    #{plus_minute_unix(date, 3)},#{base_asset},#{quote_asset},6197.939996238564,6222.227841407011,6192.793826728586,6217.384955634299,314.0696364399999,1945735.2372270185
    #{plus_minute_unix(date, 4)},#{base_asset},#{quote_asset},6217.384955634299,6217.993237443811,6209.168779847916,6217.993237443811,112.14874852000004,695884.867759606
    #{plus_minute_unix(date, 5)},#{base_asset},#{quote_asset},6217.993237443811,6229.089100547346,6214.9826060164205,6214.9826060164205,151.10683892,939350.748015517
    #{plus_minute_unix(date, 6)},#{base_asset},#{quote_asset},6214.9826060164205,6218.597161717178,6214.9825960397875,6217.0036048556485,38.02122108,236386.75875724945
    #{plus_minute_unix(date, 7)},#{base_asset},#{quote_asset},6217.0036048556485,6217.102504984712,6206.278670187404,6208.461799608979,45.82058862,284268.99153977534
    #{plus_minute_unix(date, 8)},#{base_asset},#{quote_asset},6208.461799608979,6208.532605936519,6189.4098304679455,6189.4098304679455,68.6445905213,425238.62707955315
    #{plus_minute_unix(date, 9)},#{base_asset},#{quote_asset},6189.4098304679455,6186.311225623817,6172.260084397845,6183.037558600886,239.76278609,1479869.5966138889
    #{plus_minute_unix(date, 10)},#{base_asset},#{quote_asset},6183.037558600886,6196.103879313986,6182.187912136396,6195.374525566966,71.90127728,444693.33296894276
    #{plus_minute_unix(date, 11)},#{base_asset},#{quote_asset},6195.374525566966,6196.611659810523,6186.919998235561,6189.526529700908,51.03264455000001,317063.86678641866
    #{plus_minute_unix(date, 12)},#{base_asset},#{quote_asset},6189.526529700908,6206.719787115138,6189.903645170898,6205.778967271624,63.31105002899999,392518.1490704502
    #{plus_minute_unix(date, 13)},#{base_asset},#{quote_asset},6205.778967271624,6236.028413641162,6205.511235110753,6212.84901891979,315.6725681114001,1964130.674653437
    #{plus_minute_unix(date, 14)},#{base_asset},#{quote_asset},6212.84901891979,6220.18630432559,6212.608620613742,6213.891154191228,82.18918875000003,510597.6406138905
    #{plus_minute_unix(date, 15)},#{base_asset},#{quote_asset},6213.891154191228,6213.952871590309,6206.129980338587,6206.327431388927,41.40101546000001,256841.3208080657
    #{plus_minute_unix(date, 16)},#{base_asset},#{quote_asset},6206.327431388927,6212.979043716915,6202.116429857085,6212.979043716915,64.09761586,397650.26869009226
    #{plus_minute_unix(date, 17)},#{base_asset},#{quote_asset},6212.979043716915,6215.819419089965,6209.099140044042,6209.099140044042,44.13442758,273937.0029895875
    #{plus_minute_unix(date, 18)},#{base_asset},#{quote_asset},6209.099140044042,6209.396411564128,6207.223419819188,6208.7051725246765,11.45305277,71041.48491074912
    #{plus_minute_unix(date, 19)},#{base_asset},#{quote_asset},6209.099140044042,6209.396411564128,6207.223419819188,6208.7051725246765,11.45305277,71041.48491074912
    """

    http_response = %HTTPoison.Response{
      status_code: 200,
      body: body,
      headers: [
        {"Content-Type", "text/csv"},
        {"X-RateLimit-Remaining-All",
         "1220397, 9500;window=1, 9500;window=60, 9500;window=3600, 38673;window=86400, 1220397;window=2592000"}
      ]
    }

    {:ok, http_response}
  end

  def open_interest_data(market, instrument, timestamp, limit) do
    fragments =
      Enum.map(0..(limit - 1), fn shift ->
        """
        {
          "UNIT": "HOUR",
          "TIMESTAMP": #{timestamp - shift * 3600},
          "TYPE": "944",
          "MARKET": "#{market}",
          "INSTRUMENT": "ETHUSD_PERP",
          "MAPPED_INSTRUMENT": "#{instrument}",
          "INDEX_UNDERLYING": "ETH",
          "QUOTE_CURRENCY": "USD",
          "SETTLEMENT_CURRENCY": "ETH",
          "CONTRACT_CURRENCY": "USD",
          "OPEN_SETTLEMENT": 144118.03702499828,
          "OPEN_MARK_PRICE": 1322.89,
          "OPEN_QUOTE": 190652310,
          "HIGH_SETTLEMENT": 144349.51318039416,
          "HIGH_SETTLEMENT_MARK_PRICE": 1322.17072157,
          "HIGH_MARK_PRICE": 1333.65720018,
          "HIGH_MARK_PRICE_SETTLEMENT": 141520.45966124302,
          "HIGH_QUOTE": 190854700,
          "HIGH_QUOTE_MARK_PRICE": 1322.17072157,
          "LOW_SETTLEMENT": 140745.47411301592,
          "LOW_SETTLEMENT_MARK_PRICE": 1332.53698694,
          "LOW_MARK_PRICE": 1320.5277073,
          "LOW_MARK_PRICE_SETTLEMENT": 144019.95425666144,
          "LOW_QUOTE": 187529820,
          "LOW_QUOTE_MARK_PRICE": 1332.36945193,
          "CLOSE_SETTLEMENT": 140817.31540725136,
          "CLOSE_MARK_PRICE": 1332.98969276,
          "CLOSE_QUOTE": 187708030,
          "FIRST_MESSAGE_TIMESTAMP": 1665360014,
          "FIRST_MESSAGE_SETTLEMENT": 144109.026449667,
          "FIRST_MESSAGE_MARK_PRICE": 1322.89,
          "FIRST_MESSAGE_QUOTE": 190640390,
          "HIGH_MESSAGE_SETTLEMENT": 144349.51318039416,
          "HIGH_MESSAGE_SETTLEMENT_MARK_PRICE": 1322.17072157,
          "HIGH_MESSAGE_SETTLEMENT_TIMESTAMP": 1665360136,
          "HIGH_MESSAGE_MARK_PRICE": 1333.65720018,
          "HIGH_MESSAGE_MARK_PRICE_SETTLEMENT": 141520.45966124302,
          "HIGH_MESSAGE_MARK_PRICE_TIMESTAMP": 1665362957,
          "HIGH_MESSAGE_QUOTE": 190854700,
          "HIGH_MESSAGE_QUOTE_MARK_PRICE": 1322.17072157,
          "HIGH_MESSAGE_QUOTE_TIMESTAMP": 1665360136,
          "LOW_MESSAGE_SETTLEMENT": 140745.47411301592,
          "LOW_MESSAGE_SETTLEMENT_MARK_PRICE": 1332.53698694,
          "LOW_MESSAGE_SETTLEMENT_TIMESTAMP": 1665363502,
          "LOW_MESSAGE_MARK_PRICE": 1320.5277073,
          "LOW_MESSAGE_MARK_PRICE_SETTLEMENT": 144019.95425666144,
          "LOW_MESSAGE_MARK_PRICE_TIMESTAMP": 1665360557,
          "LOW_MESSAGE_QUOTE": 187529820,
          "LOW_MESSAGE_QUOTE_MARK_PRICE": 1332.36945193,
          "LOW_MESSAGE_QUOTE_TIMESTAMP": 1665363482,
          "LAST_MESSAGE_TIMESTAMP": 1665363588,
          "LAST_MESSAGE_SETTLEMENT": 140817.31540725136,
          "LAST_MESSAGE_MARK_PRICE": 1332.98969276,
          "LAST_MESSAGE_QUOTE": 187708030,
          "TOTAL_OPEN_INTEREST_UPDATES": 172
        }
        """
      end)

    json = """
    {
      "Data": [
        #{Enum.join(fragments, ",\n")}
      ],
      "Err": {}
    }
    """

    http_response = %HTTPoison.Response{
      status_code: 200,
      body: json,
      headers: [
        {"Content-Type", "application/json; charset=UTF-8"},
        {"X-RateLimit-Remaining-All",
         "1220397, 9500;window=1, 9500;window=60, 9500;window=3600, 38673;window=86400, 1220397;window=2592000"}
      ]
    }

    {:ok, http_response}
  end

  def funding_rate_data(market, instrument, timestamp, limit) do
    fragments =
      Enum.map(0..(limit - 1), fn shift ->
        """
        {
          "UNIT": "MINUTE",
          "TIMESTAMP": #{timestamp - shift * 3600},
          "TYPE": "934",
          "MARKET": "#{market}",
          "INSTRUMENT": "#{instrument}",
          "MAPPED_INSTRUMENT": "ETH-USDT-VANILLA-PERPETUAL",
          "INDEX_UNDERLYING": "ETH",
          "QUOTE_CURRENCY": "USDT",
          "SETTLEMENT_CURRENCY": "USDT",
          "CONTRACT_CURRENCY": "ETH",
          "INTERVAL_MS": 28800000,
          "OPEN": 1.29e-05,
          "HIGH": 1.29e-05,
          "LOW": 1.29e-05,
          "CLOSE": 0.01,
          "TOTAL_FUNDING_RATE_UPDATES": 0
        }
        """
      end)

    json = """
    {
      "Data": [
        #{Enum.join(fragments, ",\n")}
      ],
      "Err": {}
    }
    """

    http_response = %HTTPoison.Response{
      status_code: 200,
      body: json,
      headers: [
        {"Content-Type", "application/json; charset=UTF-8"},
        {"X-RateLimit-Remaining-All",
         "1220397, 9500;window=1, 9500;window=60, 9500;window=3600, 38673;window=86400, 1220397;window=2592000"}
      ]
    }

    {:ok, http_response}
  end

  defp plus_minute_unix(date, minutes) do
    # receive a date Date and minutes int and return unix timestamp that is minutes after date
    date
    |> DateTime.new!(~T[00:00:00])
    |> Timex.shift(minutes: minutes)
    |> DateTime.to_unix()
  end
end
