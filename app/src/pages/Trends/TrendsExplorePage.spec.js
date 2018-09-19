/* eslint-env jest */
import React from 'react'
import toJson from 'enzyme-to-json'
import { shallow, mount } from 'enzyme'
import TrendsExplorePage, { calculateNewSources } from './TrendsExplorePage'

describe('TrendsExplorePage', () => {
  it('smoke', () => {
    const mockCb = jest.fn()
    const wrapper = shallow(<TrendsExplorePage />)
    expect(toJson(wrapper)).toMatchSnapshot()
  })
})
