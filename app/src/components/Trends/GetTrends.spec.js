/* eslint-env jest */
import { normalizeTopic } from './GetTrends'

describe('normalizeTopic', () => {
  it('should return initial data, if has OR/AND/()', () => {
    const data = '(XRP OR Ripple OR XLM OR ETH) AND top'
    expect(normalizeTopic(data)).toEqual(data)
  })

  it('should return initial data, if has OR/AND/()', () => {
    const data = '(santa monica)'
    expect(normalizeTopic(data)).toEqual(`"${data}"`)
  })

  it('should return initial data wrapped "", if has non closed brackets', () => {
    const data = 'santa monica :)'
    expect(normalizeTopic(data)).toEqual(`"${data}"`)
  })

  it('should return initial data, if one word', () => {
    const data = 'ICO'
    expect(normalizeTopic(data)).toEqual(data)
  })

  it('should return initial data wrapped "", if 2 or more words without OR/AND/()', () => {
    const data = 'ICO CHECK'
    expect(normalizeTopic(data)).toEqual(`"${data}"`)
  })
})
