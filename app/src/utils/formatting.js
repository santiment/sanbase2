const formatCryptoCurrency = (currency, amount) => `${currency} ${amount}`

const formatBTC = price => {
  price = parseFloat(price)
  const precision = price > 1 ? 2 : 8

  return parseFloat(price.toFixed(precision))
}

const formatSAN = price => {
  const value = price / 10000000000

  return value % 1 === 0 ? `${value}.000` : `${value}`
}

const formatNumber = (amount, options = {}) => {
  let value = new Intl.NumberFormat('en', {
    style: options.currency ? 'currency' : 'decimal',
    ...options
  }).format(amount)

  // Include positive +
  if (options.directionSymbol && amount >= 0) {
    value = `+${value}`
  }

  return value
}

const millify = (value, precision = 1) => {
  const suffixes = ['', 'K', 'M', 'B', 'T']
  value = Number(value)
  if (value === 0) return value.toString()

  let exponent = Math.floor(Math.log(Math.abs(value)) / Math.log(1000))
  if (exponent < 0) {
    exponent = 0
  } else if (exponent >= suffixes.length) {
    exponent = suffixes.length - 1
  }

  const prettifiedValue = value / Math.pow(1000, exponent)
  precision = prettifiedValue % 1 === 0 ? 0 : precision

  return `${Number(prettifiedValue.toFixed(precision))}${suffixes[exponent]}`
}

export { formatCryptoCurrency, formatBTC, formatSAN, formatNumber, millify }
