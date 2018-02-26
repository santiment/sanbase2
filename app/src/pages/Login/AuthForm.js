import React, { Fragment } from 'react'
import {
  Message,
  Button,
  Icon
} from 'semantic-ui-react'
import metamaskIcon from '../../assets/metamask-icon-64-2.png'
import './AuthForm.css'

export default ({account, error = false, pending = false, handleAuth}) => {
  return (
    <Fragment>
      <Message
        header='We detect you have Metamask 🎉🎉🎉'
        list={[
          'We can auth you with Metamask account. It\'s secure and easy.',
          ...[!account && `Please unlock any Metamask account.`],
          ...[account && `Your selected wallet public key is ${account}`]
        ]}
      />
      {error && <div>
        <Message
          style={{marginBottom: 10}}
          negative
          header='Apologies, there was a problem with blockchain authetication'
          content='Try again later or another login option' />
      </div>}
      {!account &&
        <Icon
          className='help-arrow-extension'
          size='massive'
          color='orange'
          name='long arrow up' />}
      {account &&
        <Button
          basic
          className='metamask-btn'
          disabled={pending}
          style={{
            display: 'flex',
            alignItems: 'center',
            paddingTop: '5px',
            paddingBottom: '5px',
            margin: '0 auto'
          }}
          onClick={handleAuth}
        ><img
          src={metamaskIcon}
          alt='metamask logo'
          width={28}
          height={28} />&nbsp;
          {pending ? 'Waiting...' : 'Sign in with Metamask'}

        </Button>}
    </Fragment>
  )
}
