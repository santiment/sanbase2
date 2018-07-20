/* eslint-env jasmine */
import { normalizeData } from './utils'

const burnRate = [
  {
    datetime: '2017-12-25T07:14:39Z',
    burnRate: '8.464401821855428E+25',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T08:37:31Z',
    burnRate: '2.775076402424953E+26',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T10:05:14Z',
    burnRate: '2.5104407712022727E+26',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T11:32:00Z',
    burnRate: '2.3608754692409206E+26',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T12:49:07Z',
    burnRate: '1.8304575804497508E+26',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T14:10:31Z',
    burnRate: '1.331268529167392E+26',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T15:44:16Z',
    burnRate: '236.599552256402053E+25',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T17:16:35Z',
    burnRate: '6.430031677024481E+25',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T19:08:43Z',
    burnRate: '1.177947052158398E+25',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T20:55:00Z',
    burnRate: '5.083749554448418E+25',
    __typename: 'BurnRateData'
  },
  {
    datetime: '2017-12-25T22:49:41Z',
    burnRate: '2347.845653211256789E+26',
    __typename: 'BurnRateData'
  }
]

describe('normalizeOutliers', () => {
  it('should return array', () => {
    const normalizedBurnRate = normalizeData({
      data: burnRate,
      fieldName: 'burnRate'
    })
    expect(Array.isArray(normalizedBurnRate)).toBe(true)
  })

  it('should return outliers array', () => {
    const normalizedBurnRate = normalizeData({
      data: burnRate,
      fieldName: 'burnRate',
      filter: 'only'
    })
    expect(normalizedBurnRate.length).toBe(2)
    expect(normalizedBurnRate[0].datetime).toBe('2017-12-25T15:44:16Z')
  })
})
