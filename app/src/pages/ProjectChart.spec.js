/* eslint-env jest */
import React from 'react'
import { shallow, mount } from 'enzyme'
import toJson from 'enzyme-to-json'
import { ProjectChart } from './ProjectChart'

const historyData = [{
  priceBtc: 123,
  datetime: '2017-12-27T21:45Z'
}, {
  priceBtc: 123,
  datetime: '2017-12-27T21:45Z'
}]

describe('ProjectChart component', () => {
  it('(smoke) it should render correctly', () => {
    const chart = shallow(<ProjectChart
      history={{
        isLoading: false,
        isError: false,
        data: historyData
      }} />)
    expect(toJson(chart)).toMatchSnapshot()
  })

  describe('Loading State', () => {
    it('it should render correctly with loading prop', () => {
      const chart = mount(<ProjectChart
        history={{
          isLoading: true,
          isError: false,
          data: historyData
        }} />)
      expect(toJson(chart)).toMatchSnapshot()
    })

    it('it should render correctly withour history prop', () => {
      const chart = mount(<ProjectChart />)
      expect(toJson(chart)).toMatchSnapshot()
    })
  })

  describe('Error State', () => {
    it('it should render correctly with error message', () => {
      const chart = mount(<ProjectChart
        history={{
          isLoading: false,
          isError: true,
          errorMessage: '400 error',
          data: historyData
        }} />)
      expect(toJson(chart)).toMatchSnapshot()
    })
  })
})
