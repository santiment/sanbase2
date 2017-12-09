import * as actions from './../actions/types'
import { checkIsLoggedIn } from './../pages/UserSelectors'

const ignoredPages = ['/privacy-policy', '/roadmap']

const handleRouter = (action$, store, { client }) =>
  action$
    .ofType('@@router/LOCATION_CHANGE')
    .filter(({ payload = { pathname: '' } }) => {
      const state = store.getState()
      const { privacyPolicyAccepted = false } = state.user.data
      const isLoggedIn = checkIsLoggedIn(state)

      return (
        !state.user.isLoading &&
        isLoggedIn &&
        !privacyPolicyAccepted &&
        !ignoredPages.includes(payload.pathname)
      )
    })
    .map(() => ({
      type: actions.APP_SHOW_GDPR_MODAL
    }))

export default handleRouter
