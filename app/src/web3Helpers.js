let prevSelectedAccount = null

const getWeb3 = () => {
  return new Promise(async (resolve, reject) => {
    // Modern dapp browsers
    if (window.ethereum) {
      try {
        // Request account access if needed}
        await window.ethereum.enable()
        resolve(new Web3(window.ethereum)) // eslint-disable-line
      } catch (error) {
        // User denied access
        reject(error)
      }
    }
    // Legacy dapp browsers
    else if (window.web3) {
      resolve(new Web3(web3.currentProvider)) // eslint-disable-line
    }
    return resolve(null)
  })
}

export const hasMetamask = () => {
  // Modern dapp browsers
  if (window.ethereum) {
    return window.ethereum.isMetaMask
  }
  // Legacy dapp browsers
  else if (window.web3) {
    return window.web3.currentProvider.isMetaMask
  }
  return false
}

export const setupWeb3 = async cbk => {
  const localWeb3 = await getWeb3()
  // Why the interval method here? ==> https://github.com/MetaMask/faq/blob/master/DEVELOPERS.md
  setInterval(() => {
    const selectedAccount = localWeb3.eth.accounts[0]
    if (prevSelectedAccount !== selectedAccount) {
      prevSelectedAccount = selectedAccount
      cbk(false, selectedAccount || null)
    }
  }, 100)
}

export const signMessage = async account => {
  const message = `Login in Santiment with address ${account}`
  const localWeb3 = await getWeb3()
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
