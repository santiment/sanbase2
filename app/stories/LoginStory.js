import React from 'react'
import { storiesOf } from '@storybook/react'
import { Login } from './../src/pages/Login/Login.js'

storiesOf('Login', module)
  .add('as page', () => (
    <div>
      <Login
        user={{
          account: null,
          data: {},
          hasMetamask: false,
          isLoading: true,
          error: false
        }}
      />
    </div>
  ))
