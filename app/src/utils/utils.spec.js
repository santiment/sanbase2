/* eslint-env jest */
import moment from 'moment'
import { findIndexByDatetime, millify } from './utils.js'

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
