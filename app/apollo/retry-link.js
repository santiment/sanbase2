import { RetryLink } from 'apollo-link-retry'

const retryLink = new RetryLink({
  delay: {
    initial: 500,
    max: Infinity,
    jitter: true
  },
  attempts: (count, operation, error) => {
    const max = operation.getContext().maxAttempts || 10000
    return !!error && count < max && operation.getContext().isRetriable
  }
})

export default retryLink
