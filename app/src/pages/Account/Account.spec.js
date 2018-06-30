/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { UnwrappedAccount as Account } from './Account'

const userWithoutEmail = {
  username: '0xjsadhf92fhk2fjhe',
  email: null
}
const userWithEmail = {
  username: '0xjsadhf92fhk2fjhe',
  email: 'test@gla.com'
}

describe('Account container', () => {
  xit('it should render correctly', () => {
    const account = shallow(<Account
      user={userWithoutEmail}
      loading={false} />)
    expect(toJson(account)).toMatchSnapshot()
  })
  describe('Form status messages', () => {
    it('should render no mesages initialy when client have an email', () => {
      const wrapper = shallow(<Account user={userWithEmail} />)
      expect(wrapper.find('.account-message').exists()).toBe(false)
    })
    it('should render dashboard mobile access message when client do not have an email', () => {
      const wrapper = shallow(<Account user={userWithoutEmail} />)
      expect(wrapper.find('.account-message__dashboard').exists()).toBe(true)
    })
    it('should render email error message', () => {
      const wrapper = shallow(<Account user={userWithEmail} />)
      wrapper.setState({ emailForm: { ERROR: true } })
      expect(wrapper.find('.account-message__email_error').exists()).toBe(true)
    })
    it('should render email success message', () => {
      const wrapper = shallow(<Account user={userWithEmail} />)
      wrapper.setState({ emailForm: { SUCCESS: true } })
      expect(wrapper.find('.account-message__email_success').exists()).toBe(true)
    })
    it('should render username error message', () => {
      const wrapper = shallow(<Account user={userWithEmail} />)
      wrapper.setState({ usernameForm: { ERROR: true } })
      expect(wrapper.find('.account-message__username_error').exists()).toBe(true)
    })
    it('should render username success message', () => {
      const wrapper = shallow(<Account user={userWithEmail} />)
      wrapper.setState({ usernameForm: { SUCCESS: true } })
      expect(wrapper.find('.account-message__username_success').exists()).toBe(true)
    })
  })
})
