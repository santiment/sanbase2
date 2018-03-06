/* eslint-env jest */
import moment from 'moment'
import { findIndexByDatetime, millify, calculateBTCVolume } from './utils.js'

const labels = [
  moment('2018-01-15T06:00:00Z'),
  moment('2018-01-12T06:00:00Z'),
  moment('2018-01-11T18:00:00Z')
]

describe('findIndexByDatetime', () => {
  it('should return right index by datetime', () => {
    expect(findIndexByDatetime(labels, '2018-01-11T18:00:00Z')).toEqual(2)
  })

  it('should return -1, if labels array doesnt have datetime', () => {
    expect(findIndexByDatetime(labels, '2017-01-11T18:00:00Z')).toEqual(-1)
  })

  it('should return -1, if labels array is empty', () => {
    expect(findIndexByDatetime([], '2017-01-11T18:00:00Z')).toEqual(-1)
  })
})

describe('Units', () => {
  it('identifies hundreds', () => expect(millify(100)).toEqual(100))
  it('identifies thousands', () => expect(millify(1000)).toEqual('1K'))
  it('identifies millions', () => expect(millify(1000000)).toEqual('1M'))
  it('identifies billions', () => expect(millify(1000000000)).toEqual('1B'))
  it('identifies trillions', () => expect(millify(1000000000000)).toEqual('1T'))
})

describe('Decimal places', () => {
  it('defaults to 1 decimal place', () => expect(millify(2500)).toEqual('2.5K'))
  it('returns desired decimal place', () => expect(millify(3333, 3)).toEqual('3.333K'))
})

describe('Variety', () => {
  it('can handle negative numbers', () => expect(millify(-2000)).toEqual('-2K'))
})

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

describe('calculateBTCVolume', () => {
  it('should return volume in BTC', () => {
    expect(calculateBTCVolume(historyPrice[0])).toEqual(308.34861283195977)
  })
})
