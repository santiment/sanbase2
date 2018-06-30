/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { UnwrappedAccount as Account } from './rAccount'

describe('Account container', () => {
  it('it should render correctly', () => {
    const account = shallow(<Account
      user={{
        username: '0xjsadhf92fhk2fjhe',
        email: null
      }}
      loading={false} />)
    expect(toJson(account)).toMatchSnapshot()
  })
})
