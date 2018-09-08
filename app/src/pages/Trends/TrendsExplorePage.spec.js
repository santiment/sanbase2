/* eslint-env jest */
import React from 'react'
import toJson from 'enzyme-to-json'
import { shallow, mount } from 'enzyme'
import TrendsExplorePage from './TrendsExplorePage'

describe('TrendsExplorePage', () => {
  it('smoke', () => {
    const mockCb = jest.fn()
    const wrapper = shallow(<TrendsExplorePage />)
    expect(toJson(wrapper)).toMatchSnapshot()
  })

  describe('calculateNewSources', () => {
    const sources = ['merged', 'telegram', 'reddit']

    it("it should return rest sources if clicked on 'merged' and 'merged' is actived", () => {
      const newSelected = TrendsExplorePage.calculateNewSources({
        sources,
        source: 'merged',
        selectedSources: 'merged'
      })
      expect(JSON.stringify(newSelected)).toBe(
        JSON.stringify(['telegram', 'reddit'])
      )
    })

    it("it should return merged sources if clicked on 'merged' and 'merged' is unactived", () => {
      const newSelected = TrendsExplorePage.calculateNewSources({
        sources,
        source: 'merged',
        selectedSources: ['reddit']
      })
      expect(JSON.stringify(newSelected)).toBe(JSON.stringify(['merged']))
    })

    it('it should return merged sources if clicked on any source and this source is last and single activated', () => {
      const newSelected = TrendsExplorePage.calculateNewSources({
        sources,
        source: 'reddit',
        selectedSources: ['reddit']
      })
      expect(JSON.stringify(newSelected)).toBe(JSON.stringify(['merged']))
    })
  })
})
