/* eslint-env jest */
import { makeItervalBounds } from './ProjectChartContainer'

describe('ProjectChartContainer', () => {
  it('makeIntervalBounds should works', () => {
    const intervalBounds = makeItervalBounds('1m')
    expect(intervalBounds.minInterval).toEqual('1h')
    const intervalBounds2 = makeItervalBounds('1d')
    expect(intervalBounds2.minInterval).toEqual('5m')
  })
})
