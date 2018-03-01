/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { Detailed } from './Detailed'

const projects = [
  {
    'id': 12,
    'name': 'Aeternity',
    'ticker': 'AE'
  },
  {
    'id': 15,
    'name': 'Aragon',
    'ticker': 'ANT'
  }
]

describe('Project detail page container', () => {
  it('it should render correctly', () => {
    const match = {
      params: {ticker: 'AE'}
    }
    const pdp = shallow(<Detailed
      projects={projects}
      projectId={12}
      Project={{
        project: {
          id: 12,
          name: 'Aragorn',
          ticker: 'AE',
          priceUsd: 10
        }
      }}
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
    const pdp = shallow(<Detailed
      match={{params: 'any-unkonown-project'}}
      projectId={null}
    />)
    expect(toJson(pdp)).toMatchSnapshot()
  })
})
