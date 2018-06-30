import React from 'react'
import { Form, Input } from 'semantic-ui-react'
import copy from 'copy-to-clipboard'

const AccountEthKeyForm = ({ user, loading }) => {
  const doesUserHaveEthAccounts = user.ethAccounts && user.ethAccounts.length > 0
  const inputValue = doesUserHaveEthAccounts ? user.ethAccounts[0].address : ''
  return (
    <Form loading={loading}>
      <Form.Field>
        <label>Eth Public Key</label>
        <Input
          input={{ readOnly: true }}
          disabled={!inputValue}
          action={{
            color: 'teal',
            labelPosition: 'right',
            icon: 'copy',
            content: 'Copy',
            onClick: () => copy(inputValue)
          }}
          defaultValue={inputValue}
        />
      </Form.Field>
    </Form>
  )
}

export default AccountEthKeyForm
