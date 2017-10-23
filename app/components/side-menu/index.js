export default (props) => (
  <div className="nav-side-menu">
      <div className="brand"><img src="/static/cashflow/img/logo_sanbase.png" width="115" height="22" alt="SANbase"/></div>
      <i className="fa fa-bars fa-2x toggle-btn" data-toggle="collapse" data-target="#menu-content"></i>
      <div className="menu-list">
          <ul id="menu-content" className="menu-content collapse out">
              <li>
                  <a href="#">
                      <i className="fa fa-home fa-md"></i> Dashboard (tbd)
                  </a>
              </li>
              <li data-toggle="collapse" data-target="#products" className="active">
                  <a href="#" className="active"><i className="fa fa-list fa-md"></i> Data-feeds <span className="arrow"></span></a>
              </li>
              <ul className="sub-menu" id="products">
                  <li><a href="#">Overview (tbd)</a></li>
                  <li className="active"><a href="#" className="active">Cash Flow</a></li>
              </ul>
              <li>
                  <a href="signals"><i className="fa fa-th fa-md"></i> Signals </a>
              </li>
              <li>
                  <a href="roadmap"><i className="fa fa-comment-o fa-md"></i> Roadmap </a>
              </li>
          </ul>
      </div>
  </div>
)