/* eslint-env jest */
import {
  simpleSort,
  sortDate,
  sortBalances
} from './sortMethods'

describe('Sort date method', () => {
  it('simple', () => {
    expect(simpleSort(5, 234)).toEqual(1)
    expect(simpleSort(234235, 234)).toEqual(-1)
    expect(simpleSort(234, 234)).toEqual(0)
  })
})

describe('Sort date method', () => {
  it('more', () => {
    const res = sortDate('2017-12-06T14:08:31.000000Z', '2017-12-06T16:08:31.000000Z')
    expect(res).toEqual(1)
  })

  it('less', () => {
    const res = sortDate('2017-12-06T20:08:31.000000Z', '2017-12-06T14:08:31.000000Z')
    expect(res).toEqual(-1)
  })

  it('equal', () => {
    const res = sortDate('2017-12-06T20:08:31.000000Z', '2017-12-06T20:08:31.000000Z')
    expect(res).toEqual(0)
  })

  it('with null', () => {
    const res = sortDate('2017-12-06T20:08:31.000000Z', null, true)
    expect(res).toEqual(1)

    const res2 = sortDate('2017-12-06T20:08:31.000000Z', null, false)
    expect(res2).toEqual(-1)
  })
})

describe('Sort multi wallets balance', () => {
  it('should works', () => {
    const a = {
      ethPrice: 1,
      wallets: [{
        balance: '0.00'
      }, {
        balance: '0.03'
      }]
    }
    const b = {
      ethPrice: 1,
      wallets: [{
        balance: '487.08'
      }, {
        balance: '1.01'
      }]
    }
    const c = {
      ethPrice: 1,
      wallets: [{
        balance: '0.00'
      }]
    }
    expect(sortBalances(a, b)).toEqual(1)
    expect(sortBalances(b, a)).toEqual(-1)
    expect(sortBalances(a, a)).toEqual(0)
    expect(sortBalances(a, c)).toEqual(-1)
  })
})
