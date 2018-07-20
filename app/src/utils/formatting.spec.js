/* eslint-env jest */
import {
  formatCryptoCurrency,
  formatBTC,
  formatSAN,
  formatNumber,
  millify
} from './formatting'

describe('formatCryptoCurrency', () => {
  it('returns properly formated string', () => {
    expect(formatCryptoCurrency('BTC', '50.123456789')).toEqual(
      'BTC 50.123456789'
    )
  })
})

describe('formatBTC', () => {
  it('parses input to float', () => {
    expect(formatBTC(50)).toEqual(50)
    expect(formatBTC('50')).toEqual(50)
  })

  it('sets the precision to 2 if the input is bigger than 1', () => {
    expect(formatBTC('50.123456789')).toEqual(50.12)
  })

  it('sets the precision to 8 if the input is less than 1', () => {
    expect(formatBTC('0.12345678123')).toEqual(0.12345678)
  })
})

describe('formatSAN', () => {
  it('parses input to float', () => {
    expect(formatSAN(200000000000)).toEqual('20.000')
    expect(formatSAN('200000000000')).toEqual('20.000')
  })

  it('formats correctly SAN balance without fraction digits', () => {
    expect(formatSAN('200000000000')).toEqual('20.000')
  })

  it('formats correctly SAN balance with fraction digits', () => {
    expect(formatSAN('200000001230')).toEqual('20.000000123')
  })
})

describe('formatNumber', () => {
  it('throws an error if input is not supported', () => {
    expect(() => formatNumber('adfada')).toThrowError(
      'Unsupported type: "adfada"'
    )
    expect(() => formatNumber('5.5 adfada')).toThrowError(
      'Unsupported type: "5.5 adfada"'
    )
    expect(() => formatNumber({ foo: 'bar' })).toThrowError(
      'Unsupported type: "[object Object]"'
    )
  })

  it('parses input to float', () => {
    expect(formatNumber(200000)).toEqual('200,000.00')
    expect(formatNumber('200000')).toEqual('200,000.00')
  })

  it('parses input as currency if one is passed', () => {
    expect(formatNumber(200000, { currency: 'USD' })).toEqual('$200,000.00')
  })

  it('adds + sign if directionSymbol is true and amount is positive', () => {
    expect(formatNumber(200000, { directionSymbol: true })).toEqual(
      '+200,000.00'
    )
    expect(
      formatNumber(200000, { currency: 'USD', directionSymbol: true })
    ).toEqual('+$200,000.00')
  })

  it('adds - sign for negative amounts', () => {
    expect(formatNumber(-200000)).toEqual('-200,000.00')
    expect(formatNumber(-200000, { currency: 'USD' })).toEqual('-$200,000.00')
  })
})

describe('millify', () => {
  it('identifies 0', () => expect(millify(0)).toEqual('0'))
  it('identifies very small numbers', () =>
    expect(millify(4.1e-16)).toEqual('0'))
  it('identifies hundreds', () => expect(millify(100)).toEqual('100'))
  it('identifies thousands', () => expect(millify(1000)).toEqual('1K'))
  it('identifies millions', () => expect(millify(1000000)).toEqual('1M'))
  it('identifies billions', () => expect(millify(1000000000)).toEqual('1B'))
  it('identifies trillions', () => expect(millify(1000000000000)).toEqual('1T'))
  it('identifies bigger than trillions', () =>
    expect(millify(10000000000000000)).toEqual('10000T'))
  it('handlea negative numbers', () => expect(millify(-2000)).toEqual('-2K'))

  it('defaults to 0 decimal places for millified integers', () =>
    expect(millify(2000)).toEqual('2K'))
  it('defaults to 1 decimal place', () => expect(millify(2500)).toEqual('2.5K'))
  it('returns desired decimal places', () =>
    expect(millify(3333, 3)).toEqual('3.333K'))
  it('trims insignificant zeroes', () =>
    expect(millify(1201, 2)).toEqual('1.2K'))
})
