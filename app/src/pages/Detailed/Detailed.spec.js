/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { Detailed } from './Detailed'

describe('Project detail page container', () => {
  it('it should render correctly', () => {
    const match = {
      params: {ticker: 'AE'}
    }
    const pdp = shallow(<Detailed
      projectId={12}
      Project={{
        project: {
          id: 12,
          name: 'Aragorn',
          ticker: 'AE',
          priceUsd: 10
        }
      }}
      user={{
        followedProjects: []
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
})
