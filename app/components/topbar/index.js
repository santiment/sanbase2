import styles from './index.scss'

export default (props) => (
  <div className="row topbar">
    <style dangerouslySetInnerHTML={{ __html: styles }}></style>
    <div className="col-lg-6">
      <div className="search" style={{'paddingTop': '24px', 'paddingLeft': '16px'}}>
        <i className="material-icons">search</i>
      </div>
    </div>
    <div className="col-lg-6">
      <ul className="nav-right pull-right list-unstyled">
        <li>
          <span className="balance">12.5 Ξ</span>
        </li>
        <li>
        </li>
      </ul>
    </div>
  </div>
)
