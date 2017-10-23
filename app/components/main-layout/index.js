import Head from './Head'
import Nav from './Nav'

export default class Layout extends React.Component {
  componentDidMount() {
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
                    display: $.fn.dataTable.Responsive.display.childRowImmediate,
                    type: ''
                }
            }

        });

    });
  }

  render() {
    return (
      <div>
        <Head />
        <Nav />
        <div className="container" id="main">
          {this.props.children}
        </div>
      </div>
    )
  }
}
