/* eslint-env jest */
import React from 'react'
import toJson from 'enzyme-to-json'
import { shallow, mount } from 'enzyme'
import TimeFilter, { TimeFilterItem } from './TimeFilter'

describe('TimeFilter component', () => {
  it('smoke', () => {
    const mockCb = jest.fn()
    const wrapper = shallow(<TimeFilter onSelectOption={mockCb} />)
    expect(toJson(wrapper)).toMatchSnapshot()
  })

  it('should be called onSelectOption, if TimeFilter option is clicked', () => {
    const mockCb = jest.fn()
    const wrapper = mount(<TimeFilter onSelectOption={mockCb} />)
    const firstTimeFilterItem = wrapper.find('.time-filter-item').at(2)
    firstTimeFilterItem.simulate('click')
    expect(mockCb).toHaveBeenCalled()
  })

  it('should change selected option, after click on not selected item', () => {
    const mockCb = jest.fn()
    const wrapper = mount(<TimeFilter onSelectOption={mockCb} />)
    expect(
      wrapper
        .find(TimeFilterItem)
        .at(2)
        .props().isSelected
    ).toBeFalsy()
    expect(
      wrapper
        .find('.time-filter-item')
        .at(2)
        .text()
    ).toBe('3m')
    const firstTimeFilterItem = wrapper.find('.time-filter-item').at(2)
    firstTimeFilterItem.simulate('click')
    expect(wrapper.state('selected')).toBe('3m')
  })

  it('should have selected option is 3m, if defaultSelected is 3m', () => {
    const wrapper = shallow(<TimeFilter defaultSelected='3m' />)
    expect(
      wrapper
        .find(TimeFilterItem)
        .at(2)
        .props().isSelected
    ).toBeTruthy()
  })
})
