export const simpleSort = (a, b) => {
  if (a === b) {
    return 0
  }
  return b > a ? 1 : -1
}

// Why we have so long sort method
// The reason, we want sort dates at the beginning
// and null values were placed after dates.
export const sortDate = (a, b, isDesc = true) => {
  if (a && b) {
    const _a = new Date(a).getTime()
    const _b = new Date(b).getTime()
    return simpleSort(_a, _b)
  }
  if (isDesc) {
    if (!a && b) {
      return -1
    }
    if (a && !b) {
      return 1
    }
  }
  if (!isDesc) {
    if (!a && b) {
      return 1
    }
    if (a && !b) {
      return -1
    }
  }
}

export const sumBalancesFromWallets = wallets => {
  return wallets.reduce((acc, val) => {
    acc += parseFloat(val.balance)
    return acc
  }, 0)
}

export const sortBalances = (a, b) => {
  const sumA = sumBalancesFromWallets(a.wallets)
  const sumB = sumBalancesFromWallets(b.wallets)
  return simpleSort(sumA, sumB)
}

export const sumTXOutFromWallets = wallets => {
  return wallets.reduce((acc, val) => {
    acc += parseFloat(val.tx_out) || 0
    return acc
  }, 0)
}

export const sortTxOut = (a, b) => {
  const _a = sumTXOutFromWallets(a)
  const _b = sumTXOutFromWallets(b)
  return simpleSort(_a, _b)
}
