import styles from './roadmap.scss'

export default ({ description, name }) => (
  <div className="row header-page">
    <style dangerouslySetInnerHTML={{ __html: styles }}></style>
    <div className="col-lg-12">
      <h1>{ name }</h1>
      <p>{ description }</p>
    </div>
    <style></style>
  </div>
)
