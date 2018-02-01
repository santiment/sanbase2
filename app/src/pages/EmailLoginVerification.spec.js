/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { EmailLoginVerification } from './EmailLoginVerification.js'

describe('EmailLoginVerification', () => {
  it('it should render correctly', () => {
    const comp = shallow(<EmailLoginVerification
      location={{
        search: '?email=anyemail@sdf.com&token=adskfu2y9f2fejfhe'
      }} />)
    expect(toJson(comp)).toMatchSnapshot()
  })
})
