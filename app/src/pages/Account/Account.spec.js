/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import { UnwrappedAccount as Account } from './Account'
import { Redirect } from 'react-router-dom'

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

  describe('Component methods', () => {
    describe('setFormStatus', () => {
      describe('emailForm statuses', () => {
        let AccountWrapper
        let AccountWrapperInstance
        let setFormStatus
        let emailForm
        beforeEach(() => {
          AccountWrapper = shallow(<Account user={{}} />)
          AccountWrapperInstance = AccountWrapper.instance()
          setFormStatus = AccountWrapperInstance.setFormStatus(AccountWrapperInstance.emailFormKey)
          emailForm = AccountWrapperInstance.emailFormKey
        })
        it('should change PENDING status ', () => {
          setFormStatus('PENDING', true)
          expect(AccountWrapper.state(emailForm).PENDING).toBe(true)
          setFormStatus('PENDING', false)
          expect(AccountWrapper.state(emailForm).PENDING).toBe(false)
        })
        it('should change ERROR status ', () => {
          setFormStatus('ERROR', true)
          expect(AccountWrapper.state(emailForm).ERROR).toBe(true)
          setFormStatus('ERROR', false)
          expect(AccountWrapper.state(emailForm).ERROR).toBe(false)
        })
        it('should change SUCCESS status ', () => {
          setFormStatus('SUCCESS', true)
          expect(AccountWrapper.state(emailForm).SUCCESS).toBe(true)
          setFormStatus('SUCCESS', false)
          expect(AccountWrapper.state(emailForm).SUCCESS).toBe(false)
        })
        it('should change only PENDING status ', () => {
          setFormStatus('PENDING', true)
          expect(AccountWrapper.state(emailForm).PENDING).toBe(true)
          expect(AccountWrapper.state(emailForm).ERROR).toBe(false)
          expect(AccountWrapper.state(emailForm).SUCCESS).toBe(false)
        })
        it('should change only ERROR status ', () => {
          setFormStatus('ERROR', true)
          expect(AccountWrapper.state(emailForm).ERROR).toBe(true)
          expect(AccountWrapper.state(emailForm).PENDING).toBe(false)
          expect(AccountWrapper.state(emailForm).SUCCESS).toBe(false)
        })
        it('should change only SUCCESS status ', () => {
          setFormStatus('SUCCESS', true)
          expect(AccountWrapper.state(emailForm).SUCCESS).toBe(true)
          expect(AccountWrapper.state(emailForm).PENDING).toBe(false)
          expect(AccountWrapper.state(emailForm).ERROR).toBe(false)
        })
      })

      describe('usernameForm statuses', () => {
        let AccountWrapper
        let AccountWrapperInstance
        let setFormStatus
        let usernameForm
        beforeEach(() => {
          AccountWrapper = shallow(<Account user={{}} />)
          AccountWrapperInstance = AccountWrapper.instance()
          setFormStatus = AccountWrapperInstance.setFormStatus(AccountWrapperInstance.usernameFormKey)
          usernameForm = AccountWrapperInstance.usernameFormKey
        })
        it('should change PENDING status ', () => {
          setFormStatus('PENDING', true)
          expect(AccountWrapper.state(usernameForm).PENDING).toBe(true)
          setFormStatus('PENDING', false)
          expect(AccountWrapper.state(usernameForm).PENDING).toBe(false)
        })
        it('should change ERROR status ', () => {
          setFormStatus('ERROR', true)
          expect(AccountWrapper.state(usernameForm).ERROR).toBe(true)
          setFormStatus('ERROR', false)
          expect(AccountWrapper.state(usernameForm).ERROR).toBe(false)
        })
        it('should change SUCCESS status ', () => {
          setFormStatus('SUCCESS', true)
          expect(AccountWrapper.state(usernameForm).SUCCESS).toBe(true)
          setFormStatus('SUCCESS', false)
          expect(AccountWrapper.state(usernameForm).SUCCESS).toBe(false)
        })
        it('should change only PENDING status ', () => {
          setFormStatus('PENDING', true)
          expect(AccountWrapper.state(usernameForm).PENDING).toBe(true)
          expect(AccountWrapper.state(usernameForm).ERROR).toBe(false)
          expect(AccountWrapper.state(usernameForm).SUCCESS).toBe(false)
        })
        it('should change only ERROR status ', () => {
          setFormStatus('ERROR', true)
          expect(AccountWrapper.state(usernameForm).ERROR).toBe(true)
          expect(AccountWrapper.state(usernameForm).PENDING).toBe(false)
          expect(AccountWrapper.state(usernameForm).SUCCESS).toBe(false)
        })
        it('should change only SUCCESS status ', () => {
          setFormStatus('SUCCESS', true)
          expect(AccountWrapper.state(usernameForm).SUCCESS).toBe(true)
          expect(AccountWrapper.state(usernameForm).PENDING).toBe(false)
          expect(AccountWrapper.state(usernameForm).ERROR).toBe(false)
        })
      })
    })
  })

  describe('User store has no data', () => {
    it('should return Redirect component', () => {
      const wrapper = shallow(<Account user={{}} />)
      expect(wrapper.type()).toBe(Redirect)
    })
    it('should redirect to "/"', () => {
      const wrapper = shallow(<Account user={{}} />)
      const redirect = wrapper.find(Redirect)
      expect(redirect.prop('to').pathname).toBe('/')
    })
  })

  describe('Form status messages', () => {
    describe('User without email', () => {
      it('should render dashboard mobile access message', () => {
        const wrapper = shallow(<Account user={userWithoutEmail} isLoggedIn />)
        expect(wrapper.find('.account-message__dashboard').exists()).toBe(true)
      })
    })
    describe('User with email', () => {
      let wrapper
      beforeEach(() => {
        wrapper = shallow(<Account user={userWithEmail} isLoggedIn />)
      })
      it('should render no mesages initialy when client have an email', () => {
        expect(wrapper.find('.account-message').exists()).toBe(false)
      })
      it('should render email error message', () => {
        wrapper.setState({ emailForm: { ERROR: true } })
        expect(wrapper.find('.account-message__email_error').exists()).toBe(true)
      })
      it('should render email success message', () => {
        wrapper.setState({ emailForm: { SUCCESS: true } })
        expect(wrapper.find('.account-message__email_success').exists()).toBe(true)
      })
      it('should render username error message', () => {
        wrapper.setState({ usernameForm: { ERROR: true } })
        expect(wrapper.find('.account-message__username_error').exists()).toBe(true)
      })
      it('should render username success message', () => {
        wrapper.setState({ usernameForm: { SUCCESS: true } })
        expect(wrapper.find('.account-message__username_success').exists()).toBe(true)
      })
    })
  })
})
