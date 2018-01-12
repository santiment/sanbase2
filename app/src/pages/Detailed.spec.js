/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { Detailed } from './Detailed'

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

describe('Project detail page container', () => {
  it('it should render correctly', () => {
    const match = {
      params: {ticker: 'ant'}
    }
    const pdp = shallow(<Detailed
      projects={projects}
      generalInfo={{
        isUnauthorized: true
      }}
      loading={false}
      PriceQuery={{
        loading: true
      }}
      TwitterData={{
        loading: true
      }}
      TwitterHistoryData={{
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
      PriceQuery={{
        loading: true
      }}
      loading={false}
      match={match}
      />)
    expect(toJson(pdp)).toMatchSnapshot()
  })
})
