/* eslint-env jasmine */
import user from 'reducers/user'

describe('reducers', () => {
  it('user should update web3 account correctly', () => {
    const nextState = user({
      account: null
    },
      {
        type: 'INIT_WEB3_ACCOUNT',
        account: '0x2347298347293847239'
      })
    expect(nextState.account).toBe('0x2347298347293847239')
  })
})
