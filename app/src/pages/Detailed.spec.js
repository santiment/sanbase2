/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { Detailed, calculateBTCVolume } from './Detailed'

const projects = [
  {
    'balance': '41994.09',
    'id': 12,
    'logo_url': 'aeternity.png',
    'market_cap_usd': '133759577.0',
    'name': 'Aeternity',
    'ticker': 'AE',
    'wallets': [
      {
        'address': '0x15c19E6c203E2c34D1EDFb26626bfc4F65eF96F0',
        'balance': '41994.09',
        'last_outgoing': null,
        'tx_out': null
      }
    ]
  },
  {
    'balance': '264617.29',
    'id': 15,
    'logo_url': 'aragon.png',
    'market_cap_usd': '66649211.0',
    'name': 'Aragon',
    'ticker': 'ANT',
    'wallets': [
      {
        'address': '0xcafE1A77e84698c83CA8931F54A755176eF75f2C',
        'balance': '264617.29',
        'last_outgoing': null,
        'tx_out': null
      }
    ]
  }
]

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

describe('Project detail page container', () => {
  it('it should render correctly', () => {
    const match = {
      params: {ticker: 'ant'}
    }
    const pdp = shallow(<Detailed
      projects={projects}
      generalInfo={{
        isUnauthorized: true,
        project: {
          priceUsd: 10
        }
      }}
      loading={false}
      TwitterData={{
        loading: true
      }}
      TwitterHistoryData={{
        loading: true
      }}
      GithubActivity={{
        loading: true
      }}
      BurnRate={{
        loading: true
      }}
      HistoryPrice={{
        loading: true
      }}
      match={match}
      />)
    expect(toJson(pdp)).toMatchSnapshot()
  })

  it('it should redirect to /', () => {
    const match = {
      params: {ticker: 'whatsaaa'}
    }
    const pdp = shallow(<Detailed
      projects={projects}
      loading={false}
      match={match}
      />)
    expect(toJson(pdp)).toMatchSnapshot()
  })
})

describe('ProjectChart utils', () => {
  it('calculateBTCVolume should return volume in BTC', () => {
    expect(calculateBTCVolume(historyPrice[0])).toEqual(308.34861283195977)
  })
})
