let prevSelectedAccount = null

export const hasMetamask = () => {
  return window.web3 && window.web3.currentProvider.isMetaMask
}

export const setupWeb3 = cbk => {
  if (!window.web3) { return }
  const web3 = new Web3(window.web3.currentProvider) // eslint-disable-line
  // Why the interval method here? ==> https://github.com/MetaMask/faq/blob/master/DEVELOPERS.md
  setInterval(() => {
    const selectedAccount = web3.eth.accounts[0]
    if (prevSelectedAccount !== selectedAccount) {
      prevSelectedAccount = selectedAccount
      cbk(false, selectedAccount || null)
    }
  }, 100)
}

export const signMessage = account => {
  const message = `Login in Santiment with address ${account}`
  const hashMessage = window.web3.sha3('\x19Ethereum Signed Message:\n' + message.length + message)
  return new Promise((resolve, reject) => {
    window.web3.personal.sign(window.web3.fromUtf8(message), account, (error, signature) => {
      if (!error) {
        resolve({
          hashMessage,
          signature
        })
      } else {
        reject(error)
      }
    })
  })
}
