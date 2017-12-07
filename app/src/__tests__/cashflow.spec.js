/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { Cashflow } from './../pages/Cashflow'

describe('Cashflow container', () => {
  it('it should render correctly', () => {
    const login = shallow(<Cashflow />)
    expect(toJson(login)).toMatchSnapshot()
  })
})
