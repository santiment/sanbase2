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

export const signMessage = account => {
  const message = `Login in Santiment with address ${account}`
  return new Promise((resolve, reject) => {
    window.web3.personal.sign(toHex(message), account, (error, res) => {
      if (!error) {
        resolve(res)
      } else {
        reject(error)
      }
    })
  })
}

// While we don't have hashMessage method in metamask web3,
// we need own hash function. eth.sha3 is not the right function
// Solved function got from utils package of web3
// https://github.com/ethereum/web3.js/blob/62dd77c7f43522eb568a001cf4c4df726f8efa69/lib/utils/utils.js

/**
 * Auto converts string value into it's hex representation.
 *
 * @method toHex
 * @param {String}
 * @return {String}
 */
const toHex = val => {
  return fromAscii(val)
}

/**
 * Should be called to get hex representation (prefixed by 0x) of ascii string
 *
 * @method fromAscii
 * @param {String} string
 * @param {Number} optional padding
 * @returns {String} hex representation of input string
 */
const fromAscii = str => {
  let hex = ''
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i)
    const n = code.toString(16)
    hex += n.length < 2 ? '0' + n : n
  }

  return '0x' + hex
}
