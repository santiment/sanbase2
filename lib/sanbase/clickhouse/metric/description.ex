defmodule Sanbase.Clickhouse.MetricAdapter.Description do
  @moduledoc false
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

  @velocity """
    Token Velocity is a metric which estimates the average frequency
    at which the tokens change hands during some period of time.

    Example:
    * Alice gives Bob 10 tokens at block 1 and
    * Bob gives Charlie 10 tokens at block 2

    The total transaction volume which is generated for block 1 and 2 is `10 + 10 = 20`
    The tokens being in circulation is actually `10` - because the same 10 tokens have been transacted.
    Token Velocity for blocks 1 and 2 is `20 / 10 = 2`
  """

  def description do
    %{"circulation" => @circulation, "velocity" => @velocity}
  end
end
