let prevSelectedAccount = null

export const hasMetamask = () => {
  return window.web3 && window.web3.currentProvider.isMetaMask
}

export const setupWeb3 = cbk => {
  if (!window.web3) { return }
  const web3 = new Web3(window.web3.currentProvider) // eslint-disable-line
  setInterval(() => {
    const selectedAccount = web3.eth.accounts[0]
    if (prevSelectedAccount !== selectedAccount) {
      prevSelectedAccount = selectedAccount
      cbk(false, selectedAccount || null)
    }
  }, 100)
}

export const signMessage = (message, account) => {
  const web3 = new Web3(window.web3.currentProvider) // eslint-disable-line
  web3.personal.sign(message, account, (error, res) => {
    console.log(res, error)
  })
}
