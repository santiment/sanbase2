export const getProjects = (allProjects = []) => (
  allProjects.filter(project => {
    const defaultFilter = project.ethAddresses &&
      project.ethAddresses.length > 0 &&
      project.rank &&
      project.volumeUsd > 0
    return defaultFilter
  })
)

export default getProjects
