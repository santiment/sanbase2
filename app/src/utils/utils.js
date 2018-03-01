export const findIndexByDatetime = (labels, datetime) => {
  return labels.findIndex(label => {
    return label.isSame(datetime)
  })
}

const suffixes = new Map()
suffixes.set(3, 'K')
suffixes.set(6, 'M')
suffixes.set(9, 'B')
suffixes.set(12, 'T')

export const millify = (ugly, decimal) => {
  // Make sure value is a number
  ugly = (num => {
    if (typeof num !== 'number') throw new Error('Input value is not a number')
    else return parseFloat(num)
  })(ugly)

  // Figure out how many digits in the integer
  const digits = Math.floor(Math.log10(Math.abs(ugly))) + 1

  // Figure out the appropriate unit for the number
  const units = ((num, zeroes) => {
    for (let z of suffixes.keys()) if (num > z) zeroes = z
    return { suffix: suffixes.get(zeroes), zeroes }
  })(digits, null)

  const pretty = ugly / Math.pow(10, units.zeroes)

  decimal = (pretty % 1 === 0) ? 2 : Math.max(1, (decimal + 1)) || 3

  if (ugly > -1000 && ugly < 1000) return ugly
  return `${parseFloat(pretty.toPrecision(decimal))}${units.suffix}`
}

export const calculateBTCVolume = ({volume, priceUsd, priceBtc}) => {
  return parseFloat(volume) / parseFloat(priceUsd) * parseFloat(priceBtc)
}

export const calculateBTCMarketcap = ({marketcap, priceUsd, priceBtc}) => {
  return parseFloat(marketcap) / parseFloat(priceUsd) * parseFloat(priceBtc)
}
