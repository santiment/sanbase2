/* eslint-env jest */
import React from 'react'
import { shallow, mount } from 'enzyme'
import toJson from 'enzyme-to-json'
import { ProjectIcon } from './ProjectIcon'

describe('ProjectIcon component', () => {
  it('(smoke) it should render correctly', () => {
    const icon = shallow(<ProjectIcon name='Cofound.it' />)
    expect(toJson(icon)).toMatchSnapshot()
    expect(icon.prop('src')).toEqual('cofound-it.png')
  })

  it('SAN icon should render correctly', () => {
    const icon = shallow(<ProjectIcon name='Santiment' />)
    expect(toJson(icon)).toMatchSnapshot()
    expect(icon.prop('src')).toEqual('santiment.png')
  })

  it('DAO.Casino icon should render correctly', () => {
    const icon = shallow(<ProjectIcon name='DAO.Casino' />)
    expect(toJson(icon)).toMatchSnapshot()
    expect(icon.prop('src')).toEqual('dao-casino.png')
  })
})
