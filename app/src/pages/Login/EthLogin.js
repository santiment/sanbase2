import React from 'react'
import AuthForm from './AuthForm'
import metamaskDownloadImg from './../../assets/download-metamask.png'

const EthLogin = ({user}) => {
  return (
    <div>
      {user.isLoading && !user.hasMetamask && <div>Loading</div>}
      {!user.hasMetamask && !user.isLoading &&
        <Message warning>
          <h4>We can't detect Metamask!</h4>
          <p>We can auth you with Metamask account. It's secure and easy.</p>
          <div className='help-links'>
            <a
              target='_blank'
              rel='noopener noreferrer'
              href='https://metamask.io/#how-it-works'>How Metamask works?</a>
            <a href='https://metamask.io/'>
              <img width={128} src={metamaskDownloadImg} alt='Metamask link' />
            </a>
          </div>
        </Message>
      }
      {user.hasMetamask && !user.token &&
        <AuthForm
          account={user.account}
          handleAuth={() => requestAuth(user.account, authWithSAN, client)} />}
    </div>
  )
}

export default EthLogin
