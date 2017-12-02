const formatNumber = (amount, currency, options = {}) => {
  let value = new Intl.NumberFormat('en', {
    style: currency ? 'currency' : 'decimal',
    currency,
    ...options
  }).format(amount)

  // Include positive +
  if (options.directionSymbol && amount >= 0) {
    value = `+${value}`
  }

  return value
}

export { formatNumber }
