/* eslint-env jest */
import React from './../node_modules/react'
import { mount } from 'enzyme'
import renderer from 'react-test-renderer'
import Header from '../components/header-page'

describe('Header', () => {
  it('Header should render correct name', () => {
    const app = mount(<Header name='check' />)
    expect(app.find('h1').text()).toEqual('check')
  })

  it('Header should render correctly', () => {
    const component = renderer.create(<Header />)
    const tree = component.toJSON()
    expect(tree).toMatchSnapshot()
  })
})
