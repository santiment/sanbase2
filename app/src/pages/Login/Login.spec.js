/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { Login } from './Login'

describe('Login container', () => {
  it('it should render loader while not loaded', () => {
    const login = shallow(
      <Login
        user={{
          account: null,
          data: {},
          hasMetamask: false,
          isLoading: true,
          error: false
        }}
      />
    )
    expect(toJson(login)).toMatchSnapshot()
  })
})
