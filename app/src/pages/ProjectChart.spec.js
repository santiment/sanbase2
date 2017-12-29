/* eslint-env jest */
import React from 'react'
import { shallow, mount } from 'enzyme'
import toJson from 'enzyme-to-json'
import { ProjectChart, calculateBTCVolume } from './ProjectChart'

const historyPrice = [
  {
    'volume': '3313025',
    'priceUsd': '2.2360575000000003',
    'priceBtc': '0.00020811349999999999',
    'marketcap': '72724491.75',
    'datetime': '2017-11-29T09:00:00Z',
    '__typename': 'PricePoint'
  },
  {
    'volume': '9865673',
    'priceUsd': '2.2590075',
    'priceBtc': '0.00020983916666666665',
    'marketcap': '73470907',
    'datetime': '2017-11-29T10:00:00Z',
    '__typename': 'PricePoint'
  },
  {
    'volume': '9940505',
    'priceUsd': '2.2839858333333334',
    'priceBtc': '0.00021024283333333333',
    'marketcap': '74283290.66666667',
    'datetime': '2017-11-29T11:00:00Z',
    '__typename': 'PricePoint'
  }
]

const historyData = [{
  priceBtc: 123,
  datetime: '2017-12-27T21:45Z'
}, {
  priceBtc: 123,
  datetime: '2017-12-27T21:45Z'
}]

describe('ProjectChart utils', () => {
  it('calculateBTCVolume should return volume in BTC', () => {
    expect(calculateBTCVolume(historyPrice[0])).toEqual(308.34861283195977)
  })
})

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
