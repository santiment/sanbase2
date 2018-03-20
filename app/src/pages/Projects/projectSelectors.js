export const isERC20 = project => (
  project &&
  project.ethAddresses &&
  project.ethAddresses.length > 0
)

export const getProjects = (allProjects = []) => (
  allProjects.filter(project => {
    const defaultFilter = isERC20(project) &&
      project.rank &&
      project.volumeUsd > 0
    return defaultFilter
  })
)

export default getProjects
