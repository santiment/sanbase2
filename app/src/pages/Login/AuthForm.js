import React from 'react'
import {
  Form,
  Message,
  Button,
  Icon
} from 'semantic-ui-react'
import metamaskIcon from '../../assets/metamask-icon-64.png'
import './AuthForm.css'

export default ({account, handleAuth}) => {
  return (
    <Form>
      <Message
        header='We detect you have Metamask 🎉🎉🎉'
        list={[
          'We can auth you with Metamask account. It\'s secure and easy.',
          ...[!account && `You need to unlock any Metamask account.`],
          ...[account && `Your selected wallet public key is ${account}`]
        ]}
      />
      {!account &&
        <Icon
          className='help-arrow-extension'
          size='massive'
          color='orange'
          name='long arrow up' />}
      {account &&
        <Button
          color='green'
          style={{
            display: 'flex',
            alignItems: 'center',
            paddingTop: '5px',
            paddingBottom: '5px'
          }}
          onClick={handleAuth}
        >Sign in with Metamask &nbsp;
          <img
            src={metamaskIcon}
            alt='metamask logo'
            width={32}
            height={32} />
        </Button>}
    </Form>
  )
}
