let prevSelectedAccount = null

export const hasMetamask = () => {
  return (
    typeof window.web3 !== 'undefined' && window.web3.currentProvider.isMetaMask
  )
}

export const setupWeb3 = cbk => {
  if (typeof window.web3 === 'undefined') {
    return
  }
  const localWeb3 = new Web3(web3.currentProvider)
  // Why the interval method here? ==> https://github.com/MetaMask/faq/blob/master/DEVELOPERS.md
  setInterval(() => {
    const selectedAccount = localWeb3.eth.accounts[0]
    if (prevSelectedAccount !== selectedAccount) {
      prevSelectedAccount = selectedAccount
      cbk(false, selectedAccount || null)
    }
  }, 100)
}

export const signMessage = account => {
  const message = `Login in Santiment with address ${account}`
  const localWeb3 = new Web3(web3.currentProvider)
  const messageHash = localWeb3.sha3(
    '\x19Ethereum Signed Message:\n' + message.length + message
  )
  return new Promise((resolve, reject) => {
    localWeb3.personal.sign(
      localWeb3.fromUtf8(message),
      account,
      (error, signature) => {
        if (!error) {
          resolve({
            messageHash,
            signature
          })
        } else {
          reject(error)
        }
      }
    )
  })
}
