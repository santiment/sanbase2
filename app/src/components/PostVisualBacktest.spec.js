/* eslint-env jest */
import React from 'react'
import { shallow, mount, render } from 'enzyme'
import toJson from 'enzyme-to-json'
import { PostVisualBacktest } from './PostVisualBacktest'

describe('PostVisualBacktest component', () => {
  it('(smoke) it should render correctly', () => {
    const component = render(<PostVisualBacktest ticker='SAN' from='aksdfjh' />)
    expect(toJson(component)).toMatchSnapshot()
    expect(component.html()).toEqual(null)
  })

  it('SAN icon should render correctly', () => {
    const component = render(
      <PostVisualBacktest
        ticker='SAN'
        change={25}
        changeProp='priceUsd'
        from='aksdfjh'
      />
    )
    expect(toJson(component)).toMatchSnapshot()
    expect(component.html()).toEqual(
      '<div class="ui horizontal label">SAN</div>priceUsd changes after publication<div class="percent-changes percent-changes--positive"><i class="fa fa-caret-up"></i>&#xA0;25.00%</div>'
    )
  })
})
