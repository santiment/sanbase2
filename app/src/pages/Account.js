import React from 'react'
import { connect } from 'react-redux'
import {
  compose,
  pure
} from 'recompose'
import {
  Form,
  Input,
  Message,
  Divider
} from 'semantic-ui-react'
import copy from 'copy-to-clipboard'
import Balance from './../components/Balance'
import './Account.css'

export const Account = ({user, loading}) => {
  return (
    <div className='page account'>
      <div className='page-head'>
        <h1>Account settings</h1>
      </div>
      <div className='panel'>
        <Form loading={loading}>
          <Form.Field disabled>
            <label>Email</label>
            <Input placeholder={user.email || ''} />
            {!user.email &&
              <Message
                warning
                header='Email is not added yet!'
                list={[
                  'For acces your dashboard from mobile device, you should add email address.'
                ]}
              />}
          </Form.Field>
          <Form.Field>
            <label>Username ( Eth Public Key )</label>
            <Input
              action={{
                color: 'teal',
                labelPosition: 'right',
                icon: 'copy',
                content: 'Copy',
                onClick: () => copy(user.username)
              }}
              defaultValue={user.username}
            />
          </Form.Field>
          <h3>Wallets</h3>
          <Divider />
          <Balance user={user} />
        </Form>
      </div>
    </div>
  )
}

const mapStateToProps = state => {
  return {
    user: state.user.data,
    loading: state.user.isLoading
  }
}

const enhance = compose(
  connect(
    mapStateToProps
  ),
  pure
)

export default enhance(Account)
