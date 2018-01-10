/* eslint-env jest */
import { getSourceLink } from './Post'

describe('getSourceLink should works', () => {
  it('should return medium.com', () => {
    expect(getSourceLink('https://medium.com/something')).toEqual('medium.com')
  })

  it('should return twitter.com', () => {
    expect(getSourceLink('https://twitter.com/MosSobyanin/status/950736865145098241')).toEqual('twitter.com')
  })
})
