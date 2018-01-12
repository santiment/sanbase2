/* eslint-env jest */
import { calculateBTCVolume } from './ProjectChartContainer'

const historyPrice = [
  {
    'volume': '3313025',
    'priceUsd': '2.2360575000000003',
    'priceBtc': '0.00020811349999999999',
    'marketcap': '72724491.75',
    'datetime': '2017-11-29T09:00:00Z',
    '__typename': 'PricePoint'
  },
  {
    'volume': '9865673',
    'priceUsd': '2.2590075',
    'priceBtc': '0.00020983916666666665',
    'marketcap': '73470907',
    'datetime': '2017-11-29T10:00:00Z',
    '__typename': 'PricePoint'
  },
  {
    'volume': '9940505',
    'priceUsd': '2.2839858333333334',
    'priceBtc': '0.00021024283333333333',
    'marketcap': '74283290.66666667',
    'datetime': '2017-11-29T11:00:00Z',
    '__typename': 'PricePoint'
  }
]

describe('ProjectChart utils', () => {
  it('calculateBTCVolume should return volume in BTC', () => {
    expect(calculateBTCVolume(historyPrice[0])).toEqual(308.34861283195977)
  })
})
