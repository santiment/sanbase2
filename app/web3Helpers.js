const isBrowser = typeof window !== 'undefined'

export const setupWeb3 = cbk => {
  if (isBrowser) {
    const web3 = new Web3(window.web3.currentProvider) // eslint-disable-line
    setInterval(() => {
      const selectedAccount = web3.eth.accounts[0]
      cbk(false, selectedAccount)
    }, 100)
  }
}

export const signMessage = (message, account) => {
  if (isBrowser) {
    const web3 = new Web3(window.web3.currentProvider) // eslint-disable-line
    web3.personal.sign(message, account, (error, res) => {
      console.log(res, error)
    })
  }
}
