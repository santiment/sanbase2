/* eslint-env jest */
import { formatNumber } from './formatting'

describe('Utils foramatting', () => {
  it('FormatNumber should correctly format SAN balance without fraction digits', () => {
    expect(formatNumber(200000000000, 'SAN')).toEqual('SAN 20.000')
  })

  it('FormatNumber should correctly format SAN balance with fracrion digits', () => {
    expect(formatNumber(200000001230, 'SAN')).toEqual('SAN 20.000000123')
  })
})
