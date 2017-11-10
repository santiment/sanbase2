import React, { Component } from 'react';
import fetch from 'isomorphic-unfetch'
import { WEBSITE_URL } from '../config'
import ProjectsTable from '../components/projects-table'
import MainHead from '../components/main-head'
import SideMenu from '../components/side-menu'
import $ from 'jquery'
import DataTable from 'datatables.net'

$.DataTable = DataTable;

class Index extends Component {
  constructor(props){
    super(props)
  }

  componentDidMount(){
    $(document).ready(function () {
      $('.table-hover').DataTable({
          "dom": "<'row'<'col-sm-7'i><'col-sm-5'f>>" +
          "<'row'<'col-sm-12'tr>>" +
          "<'row'<'col-sm-5'><'col-sm-7'>>",
          "paging": false,
          fixedHeader: true,
          language: {
              search: "_INPUT_",
              searchPlaceholder: "Search"
          },
        "order": [[ 1, "desc" ]],

          responsive: {
              details: {
                type: ''
              }
          }

      });
    });
  }

  static async getInitialProps(){
    const res = await fetch(WEBSITE_URL + '/api/cashflow')
    const data = await res.json()

    return {
      data: data
    }
  }

  render(){
    return (
      <div>
        <MainHead>
          <link rel="stylesheet" href="https://cdn.datatables.net/responsive/2.1.1/css/responsive.dataTables.min.css"/>
          <link rel="stylesheet" href="https://cdn.datatables.net/fixedheader/3.1.2/css/fixedHeader.bootstrap.min.css"/>
          <script src="https://cdn.datatables.net/responsive/2.1.1/js/dataTables.responsive.min.js"></script>
          <script src="https://cdn.datatables.net/responsive/2.1.1/js/responsive.bootstrap.min.js"></script>
          <script src="https://cdn.datatables.net/fixedheader/3.1.2/js/dataTables.fixedHeader.min.js"></script>
        </MainHead>
        <SideMenu activeItem="cashflow"/>
        <div className="container" id="main">
          <div className="row">
              <div className="col-lg-5">
                  <h1>Cash Flow</h1>
              </div>
              <div className="col-lg-7 community-actions">
                  <span className="legal">brought to you by <a href="https://santiment.net" target="_blank">Santiment</a>
                  <br />
                  NOTE: This app is a prototype. We give no guarantee data is correct as we are in active development.</span>
              </div>
          </div>
          <ProjectsTable data={ this.props.data }/>
        </div>
      </div>
    );
  }
}

export default Index
