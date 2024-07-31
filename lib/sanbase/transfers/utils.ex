defmodule Sanbase.Transfers.Utils do
  alias Sanbase.Project

  def top_wallet_transfers_address_clause(:in, opts) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "from NOT IN ({{#{arg_name}}}) AND to IN ({{#{arg_name}}})"
    if trailing_and, do: str <> " AND", else: str
  end

  def top_wallet_transfers_address_clause(:out, opts) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "from IN ({{#{arg_name}}}) AND to NOT IN ({{#{arg_name}}})"
    if trailing_and, do: str <> " AND", else: str
  end

  def top_wallet_transfers_address_clause(:all, opts) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = """
    (
      (from IN ({{#{arg_name}}}) AND NOT to IN ({{#{arg_name}}})) OR
      (NOT from IN ({{#{arg_name}}}) AND to IN ({{#{arg_name}}}))
    )
    """

    if trailing_and, do: str <> " AND", else: str
  end
end
