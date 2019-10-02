defmodule Sanbase.Clickhouse.Metric.Description do
  @circulation """
  Token circulation shows the distribution of non-transacted tokens over time.
  In other words - how many tokens are being HODLed, and for how long.

  Practical example:
  In one particular day Alice sends 20 ETH to Bob, Bob sends 10 ETH to Charlie
  and Charlie sends 5 ETH to Dean. This corresponds to the amount of tokens that have
  been HODLed for less than 1 day ("_-1d" column in the table)
  ###
     Alice  -- 20 ETH -->  Bob
                            |
                          10 ETH
                            |
                            v
     Dean <-- 5  ETH -- Charlie
  ###

  In this scenario the transaction volume is 20 + 10 + 5 = 35 ETH, though the ETH
  in circulation is 20 ETH.

  This can be explained as having twenty $1 bills. Alice sends all of them to Bob,
  Bob sends 10 of the received bills to Charlie and Charlie sends 5 of them to Dean.

  One of the most useful properities of Token Circulation is that this metric is immune
  to mixers and gives a much better view of the actual amount of tokens that are being
  transacted
  """
end
