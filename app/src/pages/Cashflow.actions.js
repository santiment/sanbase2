export const retrieveProjects = {
  types: ['LOADING_PROJECTS', 'SUCCESS_PROJECTS', 'FAILED_PROJECTS'],
  payload: {
    client: 'sanbaseClient',
    request: {
      url: `/cashflow`
    }
  }
}
