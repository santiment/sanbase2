/* eslint-env jest */
import React from 'react'
import toJson from 'enzyme-to-json'
import { shallow, mount } from 'enzyme'
import Selector, { SelectorItem } from './Selector'

const defaultOptions = ['1w', '1m', '3m', '6m', '1y', 'all']

describe('Selector component', () => {
  it('smoke', () => {
    const mockCb = jest.fn()
    const wrapper = shallow(
      <Selector options={defaultOptions} onSelectOption={mockCb} />
    )
    expect(toJson(wrapper)).toMatchSnapshot()
  })

  it('should be called onSelectOption, if Selector option is clicked', () => {
    const mockCb = jest.fn()
    const wrapper = mount(
      <Selector options={defaultOptions} onSelectOption={mockCb} />
    )
    const firstSelectorItem = wrapper.find('.selector-item').at(2)
    firstSelectorItem.simulate('click')
    expect(mockCb).toHaveBeenCalled()
  })

  it('should change selected option, after click on not selected item', () => {
    const mockCb = jest.fn()
    const wrapper = mount(
      <Selector options={defaultOptions} onSelectOption={mockCb} />
    )
    expect(
      wrapper
        .find(SelectorItem)
        .at(2)
        .props().isSelected
    ).toBeFalsy()
    expect(
      wrapper
        .find('.selector-item')
        .at(2)
        .text()
    ).toBe('3m')
    const firstSelectorItem = wrapper.find('.selector-item').at(2)
    firstSelectorItem.simulate('click')
    expect(wrapper.state('selected')).toBe('3m')
  })

  it('should have selected option is 3m, if defaultSelected is 3m', () => {
    const wrapper = shallow(
      <Selector options={defaultOptions} defaultSelected='3m' />
    )
    expect(
      wrapper
        .find(SelectorItem)
        .at(2)
        .props().isSelected
    ).toBeTruthy()
  })
})
