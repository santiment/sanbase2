/* eslint-env jest */
import React from 'react'
import { shallow, mount } from 'enzyme'
import toJson from 'enzyme-to-json'
import { ProjectChart } from './ProjectChart'
import { calculateBTCVolume } from './ProjectChartContainer'

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
      isLoading={false}
      isError={false}
      history={historyData}
      onFocusChange={() => {}} />)
    expect(toJson(chart)).toMatchSnapshot()
  })

  describe('Loading State', () => {
    it('it should render correctly with loading prop', () => {
      const chart = mount(<ProjectChart
        isLoading
        isError={false}
        onFocusChange={() => {}} />)
      expect(toJson(chart)).toMatchSnapshot()
    })

    it('it should render correctly withour history prop', () => {
      const chart = mount(<ProjectChart onFocusChange={() => {}} />)
      expect(toJson(chart)).toMatchSnapshot()
    })
  })

  describe('Error State', () => {
    it('it should render correctly with error message', () => {
      const chart = mount(<ProjectChart
        isError
        isLoading={false}
        errorMessage={'400 error'}
        history={[]}
        onFocusChange={() => {}} />)
      expect(toJson(chart)).toMatchSnapshot()
    })
  })
})
